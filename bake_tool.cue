import (
  "tool/os"
  "strings"
  "tool/cli"
)

command: {
  image: #Dubo & {
    target: ""
    args: {
      BUILD_TITLE: "Aptly image"
      BUILD_DESCRIPTION: "A dubo image for Aptly based on \(args.DEBOOTSTRAP_SUITE) (\(args.DEBOOTSTRAP_DATE))"
    }
  }
}
