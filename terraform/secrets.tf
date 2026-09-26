# Aufgabe 4: Zugangsdaten der Managed DB als Kubernetes-Secret "db-credentials"
# in den jeweiligen App-Namespace schreiben. Das Backend liest es per envFrom
# (helm/templates/backend.yaml). Das Passwort steht damit weder im Git noch in
# einer Datei - nur im Terraform-State (gitignored) und im Secret im Cluster.
resource "kubernetes_secret_v1" "db_credentials" {
  for_each = local.environments

  metadata {
    name      = "db-credentials"
    namespace = "user-mgmt-${each.key}"
  }

  data = {
    # private_host: Verbindung ueber das VPC. sslmode=require: DO erzwingt TLS.
    SPRING_DATASOURCE_URL      = "jdbc:postgresql://${digitalocean_database_cluster.postgres.private_host}:${digitalocean_database_cluster.postgres.port}/${digitalocean_database_db.app[each.key].name}?sslmode=require"
    SPRING_DATASOURCE_USERNAME = digitalocean_database_user.app[each.key].name
    SPRING_DATASOURCE_PASSWORD = digitalocean_database_user.app[each.key].password
  }

  depends_on = [postgresql_grant.schema_public]
}
