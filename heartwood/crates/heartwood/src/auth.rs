//! Microsoft sign-in: device code → Microsoft token → Xbox Live → XSTS → Minecraft services → profile.
//! The client id identifies Yumu itself; every player still signs in with their own account.

use std::time::Duration;

use serde::Deserialize;
use serde_json::json;

use crate::download::Downloader;
use crate::error::{Error, Result, now};

pub const CLIENT_ID: &str = "1c396a03-41a2-41b6-a331-bf96dc4f4b01";
const SCOPE: &str = "XboxLive.signin offline_access";
const DEVICE_CODE_URL: &str = "https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode";
const TOKEN_URL: &str = "https://login.microsoftonline.com/consumers/oauth2/v2.0/token";
const XBL_URL: &str = "https://user.auth.xboxlive.com/user/authenticate";
const XSTS_URL: &str = "https://xsts.auth.xboxlive.com/xsts/authorize";
const MC_LOGIN_URL: &str = "https://api.minecraftservices.com/authentication/login_with_xbox";
const MC_PROFILE_URL: &str = "https://api.minecraftservices.com/minecraft/profile";

#[derive(Debug, Clone, Deserialize)]
pub struct DeviceCode {
    pub user_code: String,
    pub device_code: String,
    pub verification_uri: String,
    pub interval: u64,
    pub expires_in: u64,
}

#[derive(Debug, Clone, Deserialize)]
pub struct MicrosoftTokens {
    pub access_token: String,
    pub refresh_token: String,
}

/// A Minecraft session plus the refresh token needed to get the next one.
#[derive(Debug, Clone)]
pub struct Signed {
    pub name: String,
    pub uuid: String,
    pub xuid: String,
    pub access_token: String,
    pub expires_at: u64,
    pub refresh_token: String,
}

#[derive(Deserialize)]
struct OAuthError {
    error: String,
}

pub async fn begin_device_code(downloader: &Downloader) -> Result<DeviceCode> {
    let (status, body) = downloader
        .post_form(
            DEVICE_CODE_URL,
            &[("client_id", CLIENT_ID), ("scope", SCOPE)],
        )
        .await?;
    if status != 200 {
        return Err(Error::AuthFailed(oauth_error(&body)));
    }
    parse(&body, DEVICE_CODE_URL)
}

/// Wait until the user finishes in the browser, then complete the whole chain.
pub async fn finish_device_code(downloader: &Downloader, code: &DeviceCode) -> Result<Signed> {
    let mut interval = code.interval.max(1);
    let deadline = now() + code.expires_in;
    let tokens = loop {
        tokio::time::sleep(Duration::from_secs(interval)).await;
        let (status, body) = downloader
            .post_form(
                TOKEN_URL,
                &[
                    ("grant_type", "urn:ietf:params:oauth:grant-type:device_code"),
                    ("client_id", CLIENT_ID),
                    ("device_code", &code.device_code),
                ],
            )
            .await?;
        if status == 200 {
            break parse::<MicrosoftTokens>(&body, TOKEN_URL)?;
        }
        match oauth_error(&body).as_str() {
            "authorization_pending" => {}
            "slow_down" => interval += 5,
            other => return Err(Error::AuthFailed(other.to_owned())),
        }
        if now() > deadline {
            return Err(Error::AuthFailed("expired_token".to_owned()));
        }
    };
    sign_in(downloader, tokens).await
}

/// Get a fresh Minecraft session from a stored refresh token.
pub async fn refresh(downloader: &Downloader, refresh_token: &str) -> Result<Signed> {
    let (status, body) = downloader
        .post_form(
            TOKEN_URL,
            &[
                ("grant_type", "refresh_token"),
                ("client_id", CLIENT_ID),
                ("refresh_token", refresh_token),
                ("scope", SCOPE),
            ],
        )
        .await?;
    if status != 200 {
        return Err(Error::AuthFailed(oauth_error(&body)));
    }
    sign_in(downloader, parse(&body, TOKEN_URL)?).await
}

#[derive(Deserialize)]
struct XboxResponse {
    #[serde(rename = "Token")]
    token: String,
    #[serde(rename = "DisplayClaims")]
    display_claims: DisplayClaims,
}
#[derive(Deserialize)]
struct DisplayClaims {
    xui: Vec<Xui>,
}
#[derive(Deserialize)]
struct Xui {
    uhs: String,
    #[serde(default)]
    xid: String,
}
#[derive(Deserialize)]
struct XstsError {
    #[serde(rename = "XErr")]
    code: u64,
}
#[derive(Deserialize)]
struct McLogin {
    access_token: String,
    expires_in: u64,
}
#[derive(Deserialize)]
struct Profile {
    id: String,
    name: String,
}

async fn sign_in(downloader: &Downloader, tokens: MicrosoftTokens) -> Result<Signed> {
    let xbl_body = json!({
        "Properties": {
            "AuthMethod": "RPS",
            "SiteName": "user.auth.xboxlive.com",
            "RpsTicket": format!("d={}", tokens.access_token),
        },
        "RelyingParty": "http://auth.xboxlive.com",
        "TokenType": "JWT",
    });
    let (status, body) = downloader.post_json(XBL_URL, &xbl_body, None).await?;
    if status != 200 {
        return Err(Error::AuthFailed(format!("xbox live {status}")));
    }
    let xbl: XboxResponse = parse(&body, XBL_URL)?;
    let user_hash = xbl
        .display_claims
        .xui
        .first()
        .map(|claim| claim.uhs.clone())
        .ok_or_else(|| Error::AuthFailed("xbox live returned no user".to_owned()))?;

    let xsts_body = json!({
        "Properties": { "SandboxId": "RETAIL", "UserTokens": [xbl.token] },
        "RelyingParty": "rp://api.minecraftservices.com/",
        "TokenType": "JWT",
    });
    let (status, body) = downloader.post_json(XSTS_URL, &xsts_body, None).await?;
    if status == 401 {
        return Err(
            match serde_json::from_str::<XstsError>(&body).map(|e| e.code) {
                Ok(2_148_916_233) => Error::AuthNoXbox,
                Ok(code) => Error::AuthFailed(format!("xsts {code}")),
                Err(_) => Error::AuthFailed("xsts 401".to_owned()),
            },
        );
    }
    if status != 200 {
        return Err(Error::AuthFailed(format!("xsts {status}")));
    }
    let xsts: XboxResponse = parse(&body, XSTS_URL)?;
    let xuid = xsts
        .display_claims
        .xui
        .first()
        .map(|c| c.xid.clone())
        .unwrap_or_default();

    let login_body = json!({ "identityToken": format!("XBL3.0 x={user_hash};{}", xsts.token) });
    let (status, body) = downloader
        .post_json(MC_LOGIN_URL, &login_body, None)
        .await?;
    match status {
        200 => {}
        403 => return Err(Error::AuthNotApproved),
        other => return Err(Error::AuthFailed(format!("minecraft services {other}"))),
    }
    let login: McLogin = parse(&body, MC_LOGIN_URL)?;

    let (status, body) = downloader
        .get_with_bearer(MC_PROFILE_URL, &login.access_token)
        .await?;
    match status {
        200 => {}
        404 => return Err(Error::AuthNoGame),
        other => return Err(Error::AuthFailed(format!("profile {other}"))),
    }
    let profile: Profile = parse(&body, MC_PROFILE_URL)?;
    Ok(Signed {
        name: profile.name,
        uuid: dashed(&profile.id),
        xuid,
        access_token: login.access_token,
        expires_at: now() + login.expires_in,
        refresh_token: tokens.refresh_token,
    })
}

fn oauth_error(body: &str) -> String {
    serde_json::from_str::<OAuthError>(body)
        .map_or_else(|_| body.chars().take(200).collect(), |e| e.error)
}

fn parse<T: serde::de::DeserializeOwned>(body: &str, from: &str) -> Result<T> {
    serde_json::from_str(body).map_err(|source| Error::Json {
        from: from.to_owned(),
        source,
    })
}

/// Mojang returns profile ids without dashes; the game and everyone else use the dashed form.
pub fn dashed(id: &str) -> String {
    if id.len() != 32 {
        return id.to_owned();
    }
    format!(
        "{}-{}-{}-{}-{}",
        &id[..8],
        &id[8..12],
        &id[12..16],
        &id[16..20],
        &id[20..]
    )
}
