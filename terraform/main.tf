# Aufgabe 3: Bereinigte Konfiguration des bestehenden DOKS-Clusters.
# Quelle: "terraform plan -generate-config-out=generated.tf" (Rohfassung liegt
# zur Nachvollziehbarkeit als generated.tf.raw daneben).
#
# Bereinigung gegenueber der Rohfassung:
#  - entfernt: alle "= null"-Werte, leere tags/labels
#  - entfernt: 8 deaktivierte Plugin-Bloecke (GPU/RDMA/p2p/routing). Je zwei
#    GPU-Varianten schliessen sich gegenseitig aus -> 4 Validierungsfehler.
#  - entfernt: vpc_uuid, worker_subnet_uuid, cluster_subnet, service_subnet
#    (vergibt DigitalOcean automatisch; hart codiert wuerde jeder Neuaufbau brechen)
#  - entfernt: min_nodes/max_nodes (nur relevant bei auto_scale = true)
#  - KORRIGIERT: node_count war 0 -> ein apply haette alle Nodes entfernt!
#  - parametrisiert: Name, Region, Version, Pool-Name, Groesse, Anzahl (variables.tf)

resource "digitalocean_kubernetes_cluster" "teko_doks" {
  name    = var.cluster_name
  region  = var.region
  version = var.k8s_version

  # Bewusste Cluster-Einstellungen (aus dem Ist-Zustand uebernommen)
  ha            = true  # hochverfuegbare Control Plane
  auto_upgrade  = false # Kubernetes-Version nur bewusst aendern
  surge_upgrade = true  # bei Upgrades zuerst neue Nodes, dann alte entfernen

  maintenance_policy {
    day        = "any"
    start_time = "00:00"
  }

  coredns_autoscaler {
    enabled = true
  }

  node_pool {
    name       = var.node_pool_name
    size       = var.node_size
    node_count = var.node_count
    auto_scale = false
  }
}
