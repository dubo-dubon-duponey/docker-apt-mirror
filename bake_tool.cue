package bake

command: {
  image: #Dubo & {
    args: {
      BUILD_TITLE: "Aptly image"
      BUILD_DESCRIPTION: "A dubo image for Aptly based on \(args.DEBOOTSTRAP_SUITE) (\(args.DEBOOTSTRAP_DATE))"
    }
  }
}
