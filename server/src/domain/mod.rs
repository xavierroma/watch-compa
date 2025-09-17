use std::str::FromStr;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum PayloadKind {
    CoreMotion,
    PadCoordinates,
}

impl PayloadKind {
    pub fn as_str(&self) -> &'static str {
        match self {
            PayloadKind::CoreMotion => "core-motion",
            PayloadKind::PadCoordinates => "pad-coordinates",
        }
    }
}

impl FromStr for PayloadKind {
    type Err = ();

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "core-motion" => Ok(PayloadKind::CoreMotion),
            "pad-coordinates" => Ok(PayloadKind::PadCoordinates),
            _ => Err(())
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct ChannelKey {
    pub device_id: String,
    pub kind: PayloadKind,
}


