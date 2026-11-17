use super::{ConnAuditPrimaryAuth, Connection};
use crate::{codo_trust, ipc};

impl Connection {
    // Remote control only, and only over an encrypted stream: the token is a bearer credential.
    fn codo_trust_eligible(&self) -> bool {
        self.lr.union.is_none()
            && !self.from_switch
            && self.stream.is_secured()
            && self.lr.codo_trust_token.len() == codo_trust::TOKEN_BYTES
    }

    pub(super) fn codo_trust_login(&mut self) -> bool {
        if !self.codo_trust_eligible() || !codo_trust::is_trusted(&self.lr.codo_trust_token) {
            return false;
        }
        hbb_common::log::info!("Trusted controller {} logs in without password", self.lr.my_id);
        self.set_conn_audit_primary_auth(ConnAuditPrimaryAuth::PermanentPassword);
        true
    }

    pub(super) fn codo_trust_set(&mut self, trusted: bool) {
        if !self.authorized || !self.codo_trust_eligible() {
            return;
        }
        hbb_common::log::info!("Trust controller {} -> {}", self.lr.my_id, trusted);
        codo_trust::set_trusted(
            &self.lr.codo_trust_token,
            &self.lr.my_id,
            &self.lr.my_name,
            trusted,
        );
        self.codo_trust_notify_cm();
    }

    pub(super) fn codo_trust_notify_cm(&mut self) {
        if !self.codo_trust_eligible() {
            return;
        }
        self.send_to_cm(ipc::Data::SwitchPermission {
            name: codo_trust::PERMISSION.to_owned(),
            enabled: codo_trust::is_trusted(&self.lr.codo_trust_token),
        });
    }
}
