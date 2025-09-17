use axum::{extract::{Path, State, WebSocketUpgrade}, response::IntoResponse};
use axum::extract::ws::{Message, WebSocket};
use axum::body::Bytes;
use axum::http::StatusCode;
use futures::StreamExt;
use tokio::time::{self, Duration};
use tracing::{error, info, instrument};

use crate::application::AppState;
use crate::domain::PayloadKind;

#[instrument(skip_all, fields(kind = %kind_str, device = %device_id))]
pub async fn ws_ingest(
    ws: WebSocketUpgrade,
    Path((kind_str, device_id)): Path<(String, String)>,
    State(state): State<AppState>,
) -> impl IntoResponse {
    let kind = match kind_str.parse::<PayloadKind>() {
        Ok(k) => k,
        Err(_) => return (StatusCode::BAD_REQUEST, "unknown payload kind").into_response(),
    };
    ws.on_upgrade(move |socket| handle_ingest(socket, device_id, kind, state))
}

#[instrument(skip_all, fields(kind = %kind_str, device = %device_id))]
pub async fn ws_subscribe(
    ws: WebSocketUpgrade,
    Path((kind_str, device_id)): Path<(String, String)>,
    State(state): State<AppState>,
) -> impl IntoResponse {
    let kind = match kind_str.parse::<PayloadKind>() {
        Ok(k) => k,
        Err(_) => return (StatusCode::BAD_REQUEST, "unknown payload kind").into_response(),
    };
    ws.on_upgrade(move |socket| handle_subscribe(socket, device_id, kind, state))
}

#[instrument(skip(ws, state), fields(device = %device_id, kind = %kind.as_str()))]
async fn handle_ingest(mut ws: WebSocket, device_id: String, kind: PayloadKind, state: AppState) {
    let chan = state.get_or_create_channel(&device_id, kind);

    info!("ingest connected");
    let mut inactivity = time::interval(Duration::from_secs(30));
    inactivity.set_missed_tick_behavior(time::MissedTickBehavior::Delay);

    loop {
        tokio::select! {
            Some(msg) = ws.next() => {
                match msg {
                    Ok(Message::Text(txt)) => {
                        info!(payload_len = txt.len(), "ingest text");
                        let text_string = txt.to_string();
                        {
                            let mut last = chan.last.write().await;
                            *last = Some(text_string.clone());
                        }
                        let _ = chan.tx.send(text_string);
                    }
                    Ok(Message::Binary(bin)) => {
                        info!(bytes = bin.len(), "ingest binary (assuming utf8)");
                        if let Ok(s) = std::str::from_utf8(bin.as_ref()) {
                            let txt = s.to_string();
                            {
                                let mut last = chan.last.write().await;
                                *last = Some(txt.clone());
                            }
                            let _ = chan.tx.send(txt);
                        }
                    }
                    Ok(Message::Ping(p)) => {
                        let _ = ws.send(Message::Pong(p)).await;
                    }
                    Ok(Message::Close(_)) => {
                        info!("ingest closed");
                        break;
                    }
                    Err(e) => {
                        error!(error = %e, "ingest error");
                        break;
                    }
                    _ => {}
                }
            }
            _ = inactivity.tick() => {
                if ws.send(Message::Ping(Bytes::new())).await.is_err() {
                    error!("ingest ping failed");
                    break;
                }
            }
        }
    }
}

#[instrument(skip(ws, state), fields(device = %device_id, kind = %kind.as_str()))]
async fn handle_subscribe(mut ws: WebSocket, device_id: String, kind: PayloadKind, state: AppState) {
    let chan = state.get_or_create_channel(&device_id, kind);
    let mut rx = chan.tx.subscribe();

    info!("subscriber connected");

    if let Some(last) = chan.last.read().await.clone() {
        if ws.send(Message::Text(last.into())).await.is_err() {
            error!("failed to send warm-start frame to subscriber");
            return;
        }
    }

    loop {
        tokio::select! {
            msg = ws.next() => {
                match msg {
                    Some(Ok(Message::Close(_))) => {
                        info!("subscriber closed");
                        break;
                    }
                    Some(Ok(Message::Ping(p))) => {
                        let _ = ws.send(Message::Pong(p)).await;
                    }
                    Some(Err(e)) => {
                        error!(error = %e, "subscriber ws error");
                        break;
                    }
                    None => break,
                    _ => {}
                }
            }
            Ok(txt) = rx.recv() => {
                if ws.send(Message::Text(txt.into())).await.is_err() {
                    error!("subscriber send failed");
                    break;
                }
            }
        }
    }
}


