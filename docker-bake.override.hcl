target "default" {
  inherits = ["shared"]
  args = {
    BUILD_TITLE = "Aptly image"
    BUILD_DESCRIPTION = "A dubo image for Aptly"
  }
  tags = [
    "dubodubonduponey/aptly",
  ]
}
