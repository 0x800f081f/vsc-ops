# Aufgabe 3: Den bestehenden (per doctl erstellten) Cluster in Terraform uebernehmen.
# Vorgehen:
#   1. terraform plan "-generate-config-out=generated.tf"
#      (dafuer war voruebergehend "provider = digitalocean" hier noetig, weil noch
#       kein resource-Block existierte -> sonst sucht Terraform hashicorp/digitalocean)
#   2. generated.tf analysiert/bereinigt -> main.tf (Rohfassung: generated.tf.raw)
#   3. terraform plan zeigt "1 to import, 0 to add, 0 to change, 0 to destroy"
#   4. terraform apply -> Cluster im State, keine Aenderung an der Infrastruktur
import {
  to = digitalocean_kubernetes_cluster.teko_doks
  id = var.cluster_id
}
