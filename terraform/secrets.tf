# Aufgabe 4 + 6: Zugangsdaten der Managed-Datenbanken als Kubernetes-Secrets.
# Passwoerter stehen weder im Git noch in einer Datei - nur im Terraform-State
# (gitignored) und im jeweiligen Secret im Cluster.

# Aufgabe 4: PostgreSQL fuer das Backend (user_mgmt_service)
resource "kubernetes_secret_v1" "db_credentials" {
  for_each = local.environments

  metadata {
    name      = "db-credentials"
    namespace = "user-mgmt-${each.key}"
  }

  data = {
    SPRING_DATASOURCE_URL      = "jdbc:postgresql://${digitalocean_database_cluster.postgres.private_host}:${digitalocean_database_cluster.postgres.port}/${digitalocean_database_db.app[each.key].name}?sslmode=require"
    SPRING_DATASOURCE_USERNAME = digitalocean_database_user.app[each.key].name
    SPRING_DATASOURCE_PASSWORD = digitalocean_database_user.app[each.key].password
  }

  depends_on = [postgresql_grant.schema_public]
}

# Aufgabe 6: MySQL fuer den module_service. Das Backend bekommt dieses Secret
# NICHT -> "user_mgmt_service hat keinen direkten Zugriff auf die MySQL".
resource "kubernetes_secret_v1" "module_service_db" {
  for_each = local.environments

  metadata {
    name      = "module-service-db"
    namespace = "user-mgmt-${each.key}"
  }

  data = {
    # urlencode: Sonderzeichen im generierten Passwort wuerden die URL sonst zerbrechen
    DATABASE_URL = "mysql+pymysql://${digitalocean_database_user.module_service[each.key].name}:${urlencode(digitalocean_database_user.module_service[each.key].password)}@${digitalocean_database_cluster.mysql.private_host}:${digitalocean_database_cluster.mysql.port}/${digitalocean_database_db.module_service[each.key].name}?charset=utf8mb4"
  }
}
