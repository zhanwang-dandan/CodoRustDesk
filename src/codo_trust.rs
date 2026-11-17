use base::config::keys::OPTION_CODO_TRUSTED_CONTROLLERS;
use hbb_common::{
    config::{Config, PeerConfig},
    sodiumoxide::utils,
};
use serde_derive::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

pub const PERMISSION: &str = "codo_trust";
pub const TOKEN_BYTES: usize = 32;
const PEER_OPTION: &str = "codo-trust-token";
const MAX_RECORDS: usize = 32;

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
struct Record {
    verifier: String,
    id: String,
    name: String,
    time: i64,
}

// The host keeps only this digest, so its option store never holds a usable credential.
fn verifier(token: &[u8]) -> Option<String> {
    (token.len() == TOKEN_BYTES).then(|| hex::encode(Sha256::digest(token)))
}

fn contains(records: &[Record], token: &[u8]) -> bool {
    let Some(verifier) = verifier(token) else {
        return false;
    };
    records
        .iter()
        .any(|record| utils::memcmp(record.verifier.as_bytes(), verifier.as_bytes()))
}

fn updated(
    mut records: Vec<Record>,
    token: &[u8],
    id: &str,
    name: &str,
    time: i64,
    trusted: bool,
) -> Vec<Record> {
    let Some(verifier) = verifier(token) else {
        return records;
    };
    records.retain(|record| record.verifier != verifier && record.id != id);
    if trusted {
        records.push(Record {
            verifier,
            id: id.to_owned(),
            name: name.to_owned(),
            time,
        });
        let excess = records.len().saturating_sub(MAX_RECORDS);
        records.drain(..excess);
    }
    records
}

fn records() -> Vec<Record> {
    serde_json::from_str(&Config::get_option(OPTION_CODO_TRUSTED_CONTROLLERS)).unwrap_or_default()
}

pub fn is_trusted(token: &[u8]) -> bool {
    contains(&records(), token)
}

pub fn set_trusted(token: &[u8], id: &str, name: &str, trusted: bool) {
    let records = updated(records(), token, id, name, hbb_common::get_time(), trusted);
    let value = if records.is_empty() {
        String::new()
    } else {
        match serde_json::to_string(&records) {
            Ok(value) => value,
            Err(error) => {
                hbb_common::log::error!("Failed to save trusted controllers: {error}");
                return;
            }
        }
    };
    Config::set_option(OPTION_CODO_TRUSTED_CONTROLLERS.to_owned(), value);
}

/// The per-host token this controller presents; created the first time the user
/// chooses to remember the password for that host.
pub fn client_token(id: &str, remember: bool) -> Vec<u8> {
    let mut config = PeerConfig::load(id);
    if let Some(token) = config
        .options
        .get(PEER_OPTION)
        .and_then(|value| hex::decode(value).ok())
        .filter(|token| token.len() == TOKEN_BYTES)
    {
        return token;
    }
    if !remember {
        return Vec::new();
    }
    match crate::trusted_devices::random_token() {
        Ok(token) => {
            config
                .options
                .insert(PEER_OPTION.to_owned(), hex::encode(token));
            config.store(id);
            token.to_vec()
        }
        Err(error) => {
            hbb_common::log::warn!("Failed to create a trusted-controller token: {error}");
            Vec::new()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_an_approved_token_is_trusted() {
        let (approved, other) = ([1u8; TOKEN_BYTES], [2u8; TOKEN_BYTES]);
        let records = updated(Vec::new(), &approved, "111", "Office", 1, true);
        assert!(contains(&records, &approved));
        assert!(!contains(&records, &other));
        assert!(!contains(&records, &[]));
        assert!(!contains(&records, &approved[..TOKEN_BYTES - 1]));
    }

    #[test]
    fn revoking_stops_trusting_the_controller() {
        let token = [3u8; TOKEN_BYTES];
        let records = updated(Vec::new(), &token, "111", "Office", 1, true);
        let records = updated(records, &token, "111", "Office", 2, false);
        assert!(!contains(&records, &token));
        assert!(records.is_empty());
    }

    #[test]
    fn approving_again_replaces_the_controllers_old_token() {
        let (old, new) = ([4u8; TOKEN_BYTES], [5u8; TOKEN_BYTES]);
        let records = updated(Vec::new(), &old, "111", "Office", 1, true);
        let records = updated(records, &new, "111", "Office", 2, true);
        assert!(!contains(&records, &old));
        assert!(contains(&records, &new));
        assert_eq!(records.len(), 1);
    }
}
