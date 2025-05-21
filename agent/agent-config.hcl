pid_file = "./pidfile"

vault {
  address = "http://127.0.0.1:8200"
  tls_skip_verify = true
}

auto_auth {
  #method {
  #  type = "token_file"
  #  config = {
  #    token_file_path = "/home/brycebudd/.vault-token"
  #  }
  #}
  method {
    type = "approle"
    mount_path = "auth/approle"
    config = {
      role_id_file_path   = "agent/role-id"
      secret_id_file_path = "agent/secret_id"
      remove_secret_id_file_after_reading = false
    }
  }

  sink "file" {
    config = {
      path = "/home/brycebudd/vault-agent-token"
    }
  }
}

template_config {
  static_secret_render_interval = "5m"
  exit_on_retry_failure         = true
}

#env_template "APPID_COMPONENT_APP_CERT" {
#  contents             = "{{ with secret \"secret/data/appid/component\"}}{{ .Data.data.app_cert }}{{ end }}"
#  error_on_missing_key = true
#}

#exec {
#  command                   = ["./agent/show.sh"]
#  restart_on_secret_changes = "always"
#  restart_stop_signal       = "SIGTERM"
#}
