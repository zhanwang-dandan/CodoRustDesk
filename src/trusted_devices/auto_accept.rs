//! Controllers trusted from the host's connection manager.
//!
//! When the host user clicks "Trust this device" for a connected controller, the host issues
//! a random token to that controller and keeps only its SHA-256. On a later login the
//! controller presents the token; a match is treated like the host user clicking "Accept",
//! so neither a password nor a confirmation is required.
//!
//! The controller's self-reported ID alone is never enough: the token must match too.

use super::{random_token, token_verifier};
use base::config::keys::OPTION_AUTO_ACCEPT_DEVICES;
use hbb_common::{
    anyhow::anyhow, bail, config::Config, get_time, sodiumoxide::utils, ResultType,
};
use serde_derive::{Deserialize, Serialize};
use std::sync::Mutex;

const MAX_DEVICES: usize = 128;
static LOCK: Mutex<()> = Mutex::new(());

#[derive(Clone, Serialize, Deserialize)]
pub struct Device {
    /// Hex SHA-256 of the issued token.
    pub verifier: String,
    pub id: String,
    pub name: String,
    pub platform: String,
    pub time: i64,
}

fn load() -> Vec<Device> {
    let value = Config::get_option(OPTION_AUTO_ACCEPT_DEVICES);
    if value.is_empty() {
        return Vec::new();
    }
    match serde_json::from_str(&value) {
        Ok(devices) => devices,
        Err(error) => {
            log::warn!("Ignoring unreadable auto-accept devices: {error}");
            Vec::new()
        }
    }
}

fn store(devices: &[Device]) -> ResultType<()> {
    let value = if devices.is_empty() {
        String::new()
    } else {
        serde_json::to_string(devices)?
    };
    Config::set_option(OPTION_AUTO_ACCEPT_DEVICES.to_owned(), value);
    Ok(())
}

/// Issues a token for the controller `id`, replacing any earlier one for that ID.
pub fn grant(id: &str, name: &str, platform: &str) -> ResultType<Vec<u8>> {
    if id.is_empty() {
        bail!("The controller did not report an ID");
    }
    let token = random_token()?;
    let Some(verifier) = token_verifier(&token) else {
        bail!("Could not derive the auto-accept verifier");
    };
    let _lock = LOCK
        .lock()
        .map_err(|_| anyhow!("Auto-accept storage lock is poisoned"))?;
    let mut devices = load();
    devices.retain(|device| device.id != id);
    devices.push(Device {
        verifier: hex::encode(verifier),
        id: id.to_owned(),
        name: name.to_owned(),
        platform: platform.to_owned(),
        time: get_time(),
    });
    if devices.len() > MAX_DEVICES {
        let excess = devices.len() - MAX_DEVICES;
        devices.drain(..excess);
    }
    store(&devices)?;
    Ok(token.to_vec())
}

/// Whether `token` was issued to the controller `id` and has not been revoked.
pub fn verify(token: &[u8], id: &str) -> bool {
    let Some(verifier) = token_verifier(token) else {
        return false;
    };
    let verifier = hex::encode(verifier);
    load().iter().any(|device| {
        device.id == id && utils::memcmp(device.verifier.as_bytes(), verifier.as_bytes())
    })
}
