resource "proxmox_download_file" "virtio_iso" {
  content_type = "iso"
  datastore_id = var.datastore_iso
  node_name    = var.proxmox_node
  file_name    = "virtio-win.iso"
  url          = "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
}

resource "proxmox_download_file" "win10_iso" {
  content_type = "iso"
  datastore_id = var.datastore_iso
  node_name    = var.proxmox_node
  file_name    = "Windows10.iso"
  url          = "https://software.download.prss.microsoft.com/dbazure/Win10_22H2_English_x64v1.iso?t=f0cb58f0-93f7-4ca2-8be0-83607bf9652a&P1=1786035529&P2=602&P3=2&P4=r5pXCEWsgfnw%2fNxs72EQioEoVQwiY6Ms1GwZ6IY8cbcCYfiuZ%2fV5SFkVeUVX7WJ%2fOICY3V2KJTSJtbZNombK22OCWBkLQavdVexrL8l7fzKOwUxmyxNGGgRtAyFK28Iy3fJqlCE6coJjMMFv5JH54Uwpb29q6M2A8Fu1X%2fRKaAyt9Z1oUn2AieyYX3Bo8FGq8AgZwEUxg%2fsHrrbzpVtPbvLlRREUXgKHdumUka93EcwNeW7QoXsDyAbtXITMWwf0BPTpO7xKKAxcg%2fXhp0VOrQzr%2b23nI5kQzQKy%2bltyhwYBHgMFD8b5O5A4DFbbLPK53dosJxJBSgePLn27%2fFJANQ%3d%3d"
}

resource "proxmox_download_file" "win11_iso" {
  content_type = "iso"
  datastore_id = var.datastore_iso
  node_name    = var.proxmox_node
  file_name    = "Windows11.iso"
  url          = "https://software.download.prss.microsoft.com/dbazure/Win11_25H2_English_x64_v2.iso?t=4fb97356-d66a-4b34-82c6-57c42ae7653f&P1=1786034785&P2=602&P3=2&P4=xwPMH5MT%2fsZOV9IWxtRBv4l7fGNqnpwHBzpFdqF9AFgMywMUHVV2dHxVCoOEb6nF95tqz3hDYY1YZ8OiERVXL6%2fPqHOESmTxSElWRQW534C6le%2fGMe5DvAcUx1Z6K18Jc5PnraFMKQzV6oS0zBjq5Cx0WWoE85jpR5AfJ%2f%2bE9OloMF6kmLZgpb%2f%2bIOeDCh5oqAbZ71nZz7odrgoLsX7Fx1wb5xhVRFhWoMEtflxPUV93TctqaOW84cij43am8dYTsX5J4wVkpA5Wy2zBboI65o0SLiL9yIu89GlP%2fa9ysRpqCdEQ8EWvaLkjaiQiZcrmIO6AB1D5Ne6lQCZiP%2b%2ftsQ%3d%3d"
}

resource "proxmox_download_file" "win25_iso" {
  content_type = "iso"
  datastore_id = var.datastore_iso
  node_name    = var.proxmox_node
  file_name    = "WindowsServer2025.iso"
  url          = "https://go.microsoft.com/fwlink/?linkid=2345730&clcid=0x409&culture=en-us&country=us"
}
