use std::sync::Arc;

use tokio::sync::RwLock;
use tokio::sync::broadcast;

use crate::domain::ChannelKey;

pub type Tx = broadcast::Sender<String>;

#[derive(Clone)]
pub struct ChannelRef {
    pub tx: Tx,
    pub last: Arc<RwLock<Option<String>>>,
}

pub trait ChannelStorePort: Send + Sync {
    fn get_or_create(&self, key: &ChannelKey) -> ChannelRef;
}


