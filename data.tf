// github_release for kured
data "github_release" "kured" {
  count       = var.kured_version == null ? 1 : 0
  repository  = "kured"
  owner       = "weaveworks"
  retrieve_by = "latest"
}
// github_release for kured
data "github_release" "calico" {
  count       = var.calico_version == null ? 1 : 0
  repository  = "calico"
  owner       = "projectcalico"
  retrieve_by = "latest"
}

