use std::sync::Arc;

use crate::domain::{ChannelKey, PayloadKind};
use crate::ports::{ChannelRef, ChannelStorePort};

#[derive(Clone)]
pub struct AppState {
    pub channels: Arc<dyn ChannelStorePort>,
}

impl AppState {
    pub fn get_or_create_channel(&self, device_id: &str, kind: PayloadKind) -> ChannelRef {
        let key = ChannelKey { device_id: device_id.to_string(), kind };
        self.channels.get_or_create(&key)
    }
}


