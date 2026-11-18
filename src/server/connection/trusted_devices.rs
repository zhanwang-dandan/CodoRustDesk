use super::{ConnAuditPrimaryAuth, ConnAuditTwoFactor, Connection};
use crate::trusted_devices::{
    authority::Unavailable,
    auto_accept,
    host::{self, LoginProof},
    DeviceInfo,
};
use base::message_proto::{LoginResponse, Message, Misc};
use hbb_common::{bail, tokio, ResultType};

impl Connection {
    pub(super) async fn begin_trusted_device(&mut self) -> bool {
        if self.conn_audit_primary_auth != ConnAuditPrimaryAuth::PermanentPassword
            || (!self.stream.is_secured() && !crate::common::is_direct_ip_access(&self.lr.username))
            || self.require_2fa.is_none()
            || self.from_switch
            || !hbb_common::config::Config::get_bool_option(
                base::config::keys::OPTION_ENABLE_TRUSTED_DEVICES,
            )
            || (!self.lr.trusted_device_v2_supported && self.lr.hwid.is_empty())
        {
            self.lr.trusted_device_v2_token.clear();
            return true;
        }
        let result = match LoginProof::from_login(&mut self.lr, &self.hash) {
            Ok(proof) => host::begin(proof).await,
            Err(error) => Err(error),
        };
        match result {
            Ok(Some((attempt, valid, totp))) => {
                self.trusted_device = attempt;
                self.require_2fa = Some(totp);
                if valid {
                    self.require_2fa = None;
                    self.set_conn_audit_two_factor(ConnAuditTwoFactor::TrustedDevice);
                }
                true
            }
            Ok(None) => true,
            Err(error) => {
                self.send_login_error(error).await;
                false
            }
        }
    }

    pub(super) async fn check_trusted_device(&mut self) -> bool {
        if let Some(attempt) = self.trusted_device.as_mut() {
            if let Err(error) = attempt.check().await {
                if self.conn_audit_two_factor == ConnAuditTwoFactor::Totp
                    && error.is::<Unavailable>()
                {
                    // Retain the ticket for the final authentication check.
                    attempt.enroll = false;
                    host::log_unavailable(&error);
                    return true;
                }
                self.trusted_device = None;
                self.send_login_error(error).await;
                self.on_close("Trusted-device authentication failed", false)
                    .await;
                return false;
            }
        }
        true
    }

    pub(super) async fn enroll_trusted_device(&mut self, response: &mut LoginResponse) -> bool {
        let Some(attempt) = self.trusted_device.take() else {
            return true;
        };
        if !response.has_peer_info()
            || self.conn_audit_primary_auth != ConnAuditPrimaryAuth::PermanentPassword
        {
            return true;
        }
        let info = DeviceInfo {
            id: self.lr.my_id.clone(),
            name: self.lr.my_name.clone(),
            platform: self.lr.my_platform.clone(),
            ..Default::default()
        };
        match attempt.finish(info).await {
            Ok(token) => {
                response.trusted_device_v2_supported = self.lr.trusted_device_v2_supported;
                response.trusted_device_v2_token = token.into();
                true
            }
            Err(error) => {
                if self.conn_audit_two_factor == ConnAuditTwoFactor::Totp
                    && error.is::<Unavailable>()
                {
                    host::log_unavailable(&error);
                    return true;
                }
                self.send_login_error(error).await;
                self.on_close("Trusted-device enrollment failed", false)
                    .await;
                false
            }
        }
    }

    // Auto-accept skips the password, so it needs an encrypted, ID-based connection.
    fn auto_accept_channel_secured(&self) -> bool {
        self.stream.is_secured() && !crate::common::is_direct_ip_access(&self.lr.username)
    }

    /// Accepts a controller trusted from the connection manager. Must run after
    /// `handle_login_request_without_validation`, which sets `self.lr`.
    pub(super) fn try_auto_accept(&mut self) -> bool {
        // Keep the token out of the request copies kept for the session.
        let token = std::mem::take(&mut self.lr.auto_accept_token);
        if token.is_empty() || self.from_switch || !self.auto_accept_channel_secured() {
            return false;
        }
        // An OS-login terminal needs its own authorization step.
        if self.terminal && !self.lr.os_login.username.is_empty() {
            return false;
        }
        if !auto_accept::verify(&token, &self.lr.my_id) {
            return false;
        }
        log::info!("Auto-accepting trusted controller {}", self.lr.my_id);
        self.set_conn_audit_primary_auth(ConnAuditPrimaryAuth::Click);
        self.trusted_device = None;
        self.require_2fa = None;
        true
    }

    /// Trusts the connected controller at the host user's request from the connection
    /// manager, and sends it the token it presents on later logins.
    pub(super) async fn grant_auto_accept(&mut self) -> ResultType<()> {
        if !self.authorized {
            bail!("The session is not connected yet");
        }
        if !self.lr.auto_accept_supported {
            bail!("auto-accept-unsupported-tip");
        }
        if !self.auto_accept_channel_secured() {
            bail!("The connection is not encrypted; the device cannot be trusted");
        }
        let id = self.lr.my_id.clone();
        let name = self.lr.my_name.clone();
        let platform = self.lr.my_platform.clone();
        let token =
            tokio::task::spawn_blocking(move || auto_accept::grant(&id, &name, &platform))
                .await??;
        let mut misc = Misc::new();
        misc.set_auto_accept_token(token.into());
        let mut msg = Message::new();
        msg.set_misc(misc);
        self.send(msg).await;
        Ok(())
    }
}
