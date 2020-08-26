variable "PWD" {
  default = "."
}

target "default" {
  inherits = ["shared"]
  context = "${PWD}/context"
  args = {
    BUILD_TITLE = "Aptly image"
    BUILD_DESCRIPTION = "A dubo image for Aptly"
  }
  tags = [
    "dubodubonduponey/aptly",
  ]
}
