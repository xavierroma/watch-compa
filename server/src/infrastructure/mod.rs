use std::sync::Arc;

use dashmap::DashMap;
use tokio::sync::{broadcast, RwLock};

use crate::domain::ChannelKey;
use crate::ports::{ChannelRef, ChannelStorePort};

pub type Tx = broadcast::Sender<String>;

#[derive(Clone)]
pub struct Channel {
    pub tx: Tx,
    pub last: Arc<RwLock<Option<String>>>,
}

#[derive(Clone, Default)]
pub struct ChannelStore {
    channels: Arc<DashMap<ChannelKey, Channel>>,
}

impl ChannelStore {
    pub fn get_or_create(&self, key: &ChannelKey) -> Channel {
        if let Some(entry) = self.channels.get(key) {
            return entry.clone();
        }
        let (tx, _rx) = broadcast::channel::<String>(256);
        let chan = Channel { tx, last: Arc::new(RwLock::new(None)) };
        self.channels.insert(key.clone(), chan.clone());
        chan
    }
}

impl ChannelStorePort for ChannelStore {
    fn get_or_create(&self, key: &ChannelKey) -> ChannelRef {
        let chan = ChannelStore::get_or_create(self, key);
        ChannelRef { tx: chan.tx.clone(), last: chan.last.clone() }
    }
}


