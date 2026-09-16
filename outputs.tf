output "rendered_cloudinit" {
  value = data.template_file.cloudinit.rendered
}
