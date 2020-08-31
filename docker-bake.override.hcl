target "default" {
  inherits = ["shared"]
  args = {
    BUILD_TITLE = "Aptly image"
    BUILD_DESCRIPTION = "A dubo image for Aptly"
  }
  tags = [
    "dubodubonduponey/aptly",
  ]
  platforms = [
    "linux/amd64",
    "linux/arm64",
    "linux/arm/v7",
    "linux/arm/v6",
    "linux/386",
    "linux/s390x",
    "linux/ppc64el",
  ]
}
