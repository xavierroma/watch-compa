use axum::{routing::get, Router};
use std::net::SocketAddr;
use tokio::net::TcpListener;
use tower_http::trace::TraceLayer;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};
use std::sync::Arc;

use compa::application::AppState;
use compa::adapters::{ws_ingest, ws_subscribe};
use compa::infrastructure::ChannelStore;

#[tokio::main]
async fn main() {
    // Build router
    // init structured logging
    tracing_subscriber::registry()
        .with(tracing_subscriber::EnvFilter::try_from_default_env()
            .unwrap_or_else(|_| "info,tower_http=info,axum::rejection=trace".into()))
        .with(tracing_subscriber::fmt::layer().compact())
        .init();

    let store = ChannelStore::default();
    let state = AppState { channels: Arc::new(store) };
    let app = Router::new()
        // Watch (producer) connects here and sends JSON frames
        .route("/ingest/{kind}/{device_id}", get(ws_ingest))
        // Clients (consumers) connect here to receive frames
        .route("/subscribe/{kind}/{device_id}", get(ws_subscribe))
        .with_state(state)
        .layer(TraceLayer::new_for_http());
    // Bind
    let addr: SocketAddr = "0.0.0.0:3000".parse().unwrap();
    tracing::info!(%addr, "IMU WS backend listening");
    let listener = TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
