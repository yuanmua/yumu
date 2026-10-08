//! Player accounts: Microsoft accounts and, once at least one of those exists, offline accounts.
//! Tokens live in `accounts.toml` with owner-only permissions.

use md5::{Digest, Md5};
use serde::{Deserialize, Serialize};

use crate::auth;
use crate::download::{Downloader, hex};
use crate::error::{Error, Result, io, now};
use crate::instance::Store;
use crate::platform;

pub const MICROSOFT: &str = "microsoft";
pub const OFFLINE: &str = "offline";
const FILE_NAME: &str = "accounts.toml";
/// Refresh when the Minecraft token has less than this many seconds left.
const REFRESH_MARGIN: u64 = 600;
/// Development builds skip ADR 0009 so the game can be tested before Mojang approves the client id.
pub const OFFLINE_WITHOUT_MICROSOFT: bool = cfg!(feature = "dev-offline");

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Account {
    pub id: String,
    pub kind: String,
    pub name: String,
    pub uuid: String,
    pub xuid: String,
    pub access_token: String,
    pub expires_at: u64,
    pub refresh_token: String,
}

impl Default for Account {
    fn default() -> Self {
        Self {
            id: String::new(),
            kind: OFFLINE.to_owned(),
            name: String::new(),
            uuid: String::new(),
            xuid: String::new(),
            access_token: String::new(),
            expires_at: 0,
            refresh_token: String::new(),
        }
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Accounts {
    pub active: String,
    #[serde(rename = "account")]
    pub accounts: Vec<Account>,
}

/// What the game needs on its command line.
#[derive(Debug, Clone)]
pub struct Session {
    pub name: String,
    pub uuid: String,
    pub access_token: String,
    pub user_type: String,
    pub xuid: String,
}

impl Accounts {
    pub fn has_microsoft(&self) -> bool {
        self.accounts
            .iter()
            .any(|account| account.kind == MICROSOFT)
    }

    /// Insert or replace by id and make it active.
    pub fn upsert(&mut self, account: Account) {
        self.accounts.retain(|existing| existing.id != account.id);
        self.active.clone_from(&account.id);
        self.accounts.push(account);
    }

    pub fn remove(&mut self, id: &str) -> Result<()> {
        let before = self.accounts.len();
        self.accounts.retain(|account| account.id != id);
        if self.accounts.len() == before {
            return Err(Error::AccountNotFound(id.to_owned()));
        }
        if !self.has_microsoft() && !OFFLINE_WITHOUT_MICROSOFT {
            // Prism's rule: offline accounts only exist alongside a real one.
            self.accounts.retain(|account| account.kind != OFFLINE);
        }
        if !self
            .accounts
            .iter()
            .any(|account| account.id == self.active)
        {
            self.active = self
                .accounts
                .first()
                .map(|a| a.id.clone())
                .unwrap_or_default();
        }
        Ok(())
    }

    pub fn set_active(&mut self, id: &str) -> Result<()> {
        if !self.accounts.iter().any(|account| account.id == id) {
            return Err(Error::AccountNotFound(id.to_owned()));
        }
        id.clone_into(&mut self.active);
        Ok(())
    }

    /// Add an offline account; allowed only when a Microsoft account is present.
    pub fn add_offline(&mut self, name: &str) -> Result<Account> {
        if !self.has_microsoft() && !OFFLINE_WITHOUT_MICROSOFT {
            return Err(Error::OfflineRequiresMicrosoft);
        }
        let account = offline(name);
        self.upsert(account.clone());
        Ok(account)
    }
}

impl Store {
    pub async fn load_accounts(&self) -> Result<Accounts> {
        let path = self.root().join(FILE_NAME);
        match tokio::fs::read_to_string(&path).await {
            Ok(text) => toml::from_str(&text).map_err(|error| Error::Toml {
                path,
                message: error.to_string(),
            }),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(Accounts::default()),
            Err(error) => Err(io(&path)(error)),
        }
    }

    pub async fn save_accounts(&self, accounts: &Accounts) -> Result<()> {
        let path = self.root().join(FILE_NAME);
        tokio::fs::create_dir_all(self.root())
            .await
            .map_err(io(self.root()))?;
        let part = self.root().join("accounts.toml.part");
        let text = toml::to_string_pretty(accounts).map_err(|error| Error::Toml {
            path: path.clone(),
            message: error.to_string(),
        })?;
        tokio::fs::write(&part, text).await.map_err(io(&part))?;
        platform::restrict_permissions(&part).map_err(io(&part))?;
        tokio::fs::rename(&part, &path).await.map_err(io(&path))
    }
}

/// The session for the active account, refreshing Microsoft tokens when they are about to expire.
pub async fn active_session(store: &Store, downloader: &Downloader) -> Result<Session> {
    let mut accounts = store.load_accounts().await?;
    let index = accounts
        .accounts
        .iter()
        .position(|account| account.id == accounts.active)
        .ok_or(Error::AccountRequired)?;
    let account = &mut accounts.accounts[index];
    if account.kind == OFFLINE {
        return Ok(Session {
            name: account.name.clone(),
            uuid: account.uuid.clone(),
            access_token: "0".to_owned(),
            user_type: "legacy".to_owned(),
            xuid: "0".to_owned(),
        });
    }
    if account.expires_at < now() + REFRESH_MARGIN {
        let signed = auth::refresh(downloader, &account.refresh_token).await?;
        apply(account, signed);
        store.save_accounts(&accounts).await?;
    }
    let account = &accounts.accounts[index];
    Ok(Session {
        name: account.name.clone(),
        uuid: account.uuid.clone(),
        access_token: account.access_token.clone(),
        user_type: "msa".to_owned(),
        xuid: account.xuid.clone(),
    })
}

pub fn from_signed(signed: auth::Signed) -> Account {
    let mut account = Account {
        id: signed.uuid.clone(),
        kind: MICROSOFT.to_owned(),
        ..Account::default()
    };
    apply(&mut account, signed);
    account
}

fn apply(account: &mut Account, signed: auth::Signed) {
    account.name = signed.name;
    account.uuid = signed.uuid;
    account.xuid = signed.xuid;
    account.access_token = signed.access_token;
    account.expires_at = signed.expires_at;
    account.refresh_token = signed.refresh_token;
}

/// An offline account with the same UUID the vanilla server would derive for `name`.
pub fn offline(name: &str) -> Account {
    let mut bytes: [u8; 16] = Md5::digest(format!("OfflinePlayer:{name}")).into();
    bytes[6] = (bytes[6] & 0x0f) | 0x30;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    Account {
        id: format!("offline:{name}"),
        kind: OFFLINE.to_owned(),
        name: name.to_owned(),
        uuid: auth::dashed(&hex(&bytes)),
        ..Account::default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn offline_uuid_matches_vanilla() {
        // Known value for the name "Notch" produced by Java's UUID.nameUUIDFromBytes.
        assert_eq!(
            offline("Notch").uuid,
            "b50ad385-829d-3141-a216-7e7d7539ba7f"
        );
    }

    #[test]
    #[cfg_attr(
        feature = "dev-offline",
        ignore = "rule disabled in development builds"
    )]
    fn offline_requires_microsoft_and_goes_with_it() {
        let mut accounts = Accounts::default();
        assert!(matches!(
            accounts.add_offline("Steve"),
            Err(Error::OfflineRequiresMicrosoft)
        ));
        accounts.upsert(Account {
            id: "ms".into(),
            kind: MICROSOFT.into(),
            name: "Real".into(),
            ..Account::default()
        });
        accounts.add_offline("Steve").unwrap();
        assert_eq!(accounts.active, "offline:Steve");
        accounts.remove("ms").unwrap();
        assert!(
            accounts.accounts.is_empty(),
            "offline accounts leave with the last Microsoft account"
        );
    }
}
