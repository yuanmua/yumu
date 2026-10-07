//! Player accounts. Only offline accounts exist for now.

use md5::{Digest, Md5};

use crate::download::hex;

#[derive(Debug, Clone)]
pub struct Account {
    pub name: String,
    pub uuid: String,
    pub access_token: String,
    pub user_type: String,
}

/// An offline account with the same UUID the vanilla server would derive for `name`.
pub fn offline(name: &str) -> Account {
    let mut bytes: [u8; 16] = Md5::digest(format!("OfflinePlayer:{name}")).into();
    bytes[6] = (bytes[6] & 0x0f) | 0x30;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    let hex = hex(&bytes);
    Account {
        name: name.to_owned(),
        uuid: format!(
            "{}-{}-{}-{}-{}",
            &hex[..8],
            &hex[8..12],
            &hex[12..16],
            &hex[16..20],
            &hex[20..]
        ),
        access_token: "0".to_owned(),
        user_type: "legacy".to_owned(),
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn offline_uuid_matches_vanilla() {
        // Known value for the name "Notch" produced by Java's UUID.nameUUIDFromBytes.
        assert_eq!(
            super::offline("Notch").uuid,
            "b50ad385-829d-3141-a216-7e7d7539ba7f"
        );
    }
}
