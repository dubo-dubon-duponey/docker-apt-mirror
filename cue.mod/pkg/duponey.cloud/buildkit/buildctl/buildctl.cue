package buildctl

import (
	"list"
	"strings"
	"duponey.cloud/buildkit/types"
)

#Commander: {
	debug: bool | *false
	// XXX Make this more specific
	addr?: string
  // Injectable with good defaults
  no_cache: bool | *false
  progress: types.#Progress | *types.#Progress.#AUTO
	hostname: types.#Identifier | *"cake.duponey.cloud" // XXX domain?

	// Sane defaults
	resolve_mode: types.#ResolveMode | * types.#ResolveMode.#DEFAULT
	network_mode: types.#NetworkMode | * types.#NetworkMode.#SANDBOX

  // Mandatory, with sane defaults that are unlikely to need change in most cases
	dockerfile: types.#Path | *"./"
  frontend: types.#Identifier | *"dockerfile.v0"
  filename: types.#Path | *"Dockerfile"

  // Mandatory
	context:  types.#Path

	// XXX not completely sure what that controls - domain?
  trace?: types.#Identifier
  // XXX should be arrays and honor multiple
  cache_to?: types.#CacheTo
  cache_from?: types.#CacheFrom

	platforms?: types.#Platforms
  target?: types.#Identifier
  tarball?: types.#Tarball
  directory?: types.#Path

  // Args
  tags: [...types.#Image]
  hosts: types.#Hosts
	args: types.#Args
  secrets: types.#Secrets

  secret_path: types.#Path | *"/tmp/"

	run: ["buildctl"] +
		[if addr != _|_ {"--addr"}] + [if addr != _|_ {addr}] +
		[if debug == true {"--debug"}] +
		// [if tlsservername != _|_ {"--tlsservername"}] + [if tlsservername != _|_ {tlsservername}] +
		// [if tlscacert != _|_ {"--tlscacert"}] + [if tlscacert != _|_ {tlscacert}] +
		// [if tlscert != _|_ {"--tlscert"}] + [if tlscert != _|_ {tlscert}] +
		// [if tlskey != _|_ {"--tlskey"}] + [if tlskey != _|_ {tlskey}] +
		// [if tlsdir != _|_ {"--tlsdir"}] + [if tlsdir != _|_ {tlsdir}] +

		["build"] +
		[if no_cache == true {"--no-cache"}] +
		["--progress", progress] +
		["--opt", "hostname=\(hostname)"] +

		["--opt", "image-resolve-mode=\(resolve_mode)"] +
		["--opt", "force-network-mode=\(network_mode)"] +

		["--local", "dockerfile=\(dockerfile)"] +
		["--frontend", frontend] +
		["--opt", "filename=\(filename)"] +

		["--local", "context=\(context)"] +

		[if trace != _|_ {"--trace"}] + [if trace != _|_ {trace}] +
		[if cache_to != _|_ {"--export-cache"}] + [if cache_to != _|_ {cache_to.toString}] +
		[if cache_from != _|_ {"--import-cache"}] + [if cache_from != _|_ {cache_from.toString}] +

		[if platforms != _|_ if len(platforms) > 0 {"--opt"}] + [if platforms != _|_ if len(platforms) > 0 {"platform=" + strings.Join(platforms, ",")}] +
		// XXX buildkit only allows one output at a time right now
		[if target != _|_ {"--opt"}] + [if target != _|_ {"target=\(target)"}] +
		[if tarball.type != _|_ {"--output"}] + [if tarball.type != _|_ {"type=\(tarball.type),dest=\(tarball.location)"}] +
		[if directory != _|_ {"--output"}] + [if  directory != _|_ {"type=local,dest=\(directory)"}] +

		[if len(tags) > 0 {"--output"}] + [if len(tags) > 0 {
			"type=image,\"" + "name=" + strings.Join([for _t in tags{_t.toString}], ",") + "\",push=true,oci-mediatypes=true"
		}] +

		[if len(hosts) > 0 {"--opt"}] + [if len(hosts) > 0 {
			"add-hosts=" + strings.Join([
				for _k, _v in hosts {
					"\(_k)=\(_v)"
				}
			], ",")
		}] +

		list.Concat([
			for _k, _v in args if _v != _|_ {
				["--opt", "build-arg:\(_k)=\(_v)",]
			}
		]) +

		// XXX careful with that, as defaults will not be used
		list.Concat([
			for _k, _v in secrets if _v.content != _|_ || _v.file != _|_ {
				["--secret", "id=\(_k),src=\(secret_path)\(_k)"]
			}])
}