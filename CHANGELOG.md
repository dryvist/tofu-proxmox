# Changelog

## [3.6.0](https://github.com/dryvist/tofu-proxmox/compare/v3.5.0...v3.6.0) (2026-08-28)


### Features

* **ingress:** generate Hermes agent routes by tag; add Homepage and Glance ([#1023](https://github.com/dryvist/tofu-proxmox/issues/1023)) ([9424086](https://github.com/dryvist/tofu-proxmox/commit/9424086484613e65ab9c6a58629da6a739640936))
* **vms:** declare the Proxmox Backup Server guest in the example desired state ([#1017](https://github.com/dryvist/tofu-proxmox/issues/1017)) ([2d0d0a8](https://github.com/dryvist/tofu-proxmox/commit/2d0d0a840e926da895f1b68e5d50335c087785f1))

## [3.5.0](https://github.com/dryvist/tofu-proxmox/compare/v3.4.0...v3.5.0) (2026-08-27)


### Features

* **storage:** reject dataset quotas that exceed the pool's capacity ([#1018](https://github.com/dryvist/tofu-proxmox/issues/1018)) ([a7f6c18](https://github.com/dryvist/tofu-proxmox/commit/a7f6c18a5c58c06fe497a9d01369e8948a8bb4b5))

## [3.4.0](https://github.com/dryvist/tofu-proxmox/compare/v3.3.0...v3.4.0) (2026-08-24)


### Features

* **inventory:** publish Splunk's own disks with Proxmox-assigned names ([1bdf2ce](https://github.com/dryvist/tofu-proxmox/commit/1bdf2ce1105f344296dd4be39a267d6495454c54))

## [3.3.0](https://github.com/dryvist/tofu-proxmox/compare/v3.2.0...v3.3.0) (2026-08-24)


### Features

* **inventory:** publish each VM's datastore, and correct the schema-gate claim ([#1007](https://github.com/dryvist/tofu-proxmox/issues/1007)) ([a89f0ab](https://github.com/dryvist/tofu-proxmox/commit/a89f0ab025cb306c78a09c8f091b1852906444e9))
* **inventory:** publish every VM disk with the name Proxmox assigned ([#1009](https://github.com/dryvist/tofu-proxmox/issues/1009)) ([bc8726d](https://github.com/dryvist/tofu-proxmox/commit/bc8726d073f6a87e873475006177782ec12c2fb1))

## [3.2.0](https://github.com/dryvist/tofu-proxmox/compare/v3.1.0...v3.2.0) (2026-08-24)


### Features

* **inventory:** publish each container's effective datastore ([#1003](https://github.com/dryvist/tofu-proxmox/issues/1003)) ([bbca205](https://github.com/dryvist/tofu-proxmox/commit/bbca20582e291f99d951b14ae00b127af451b64f))


### Bug Fixes

* **storage:** publish a dataset's sparse flag instead of dropping it ([#1001](https://github.com/dryvist/tofu-proxmox/issues/1001)) ([6d30270](https://github.com/dryvist/tofu-proxmox/commit/6d30270c9bcb2c529ed8b674570e829b752cdaaf))
* **storage:** publish a pool's sparse flag, not just a dataset's ([#1002](https://github.com/dryvist/tofu-proxmox/issues/1002)) ([0989cb8](https://github.com/dryvist/tofu-proxmox/commit/0989cb8fe3296e354f8167429b84128f29943872))

## [3.1.0](https://github.com/dryvist/tofu-proxmox/compare/v3.0.0...v3.1.0) (2026-08-23)


### Features

* **inventory:** publish declared guest sizing for Nautobot ([#994](https://github.com/dryvist/tofu-proxmox/issues/994)) ([6fb590f](https://github.com/dryvist/tofu-proxmox/commit/6fb590f8ee59eca752521d6249a7820c0f8b6dc0))


### Bug Fixes

* **inventory:** publish sizing for every guest slice, not one at a time ([#996](https://github.com/dryvist/tofu-proxmox/issues/996)) ([b3e3b2f](https://github.com/dryvist/tofu-proxmox/commit/b3e3b2f39eb5f77bfaa0bdf8ccfed41dbefeca62))
* **inventory:** publish sizing for VMs, not only containers ([#995](https://github.com/dryvist/tofu-proxmox/issues/995)) ([5a6ed0d](https://github.com/dryvist/tofu-proxmox/commit/5a6ed0d49dc22c05db6a1abd64827a52b0a94174))

## [3.0.0](https://github.com/dryvist/tofu-proxmox/compare/v2.0.0...v3.0.0) (2026-08-22)


### ⚠ BREAKING CHANGES

* **storage:** node_storage.<node>.smb.managed_users entries take `secret_prefix` in place of `name` and `password_secret_env`.

### Features

* **stack:** reject container storage that its node does not offer ([#987](https://github.com/dryvist/tofu-proxmox/issues/987)) ([1636d7a](https://github.com/dryvist/tofu-proxmox/commit/1636d7a888da857179294d4c158123ff550b9f8d))
* **storage:** name SMB accounts by role, never by login name ([#988](https://github.com/dryvist/tofu-proxmox/issues/988)) ([8813af8](https://github.com/dryvist/tofu-proxmox/commit/8813af80c7b7655431e5847e66ce7cee0c464314))

## [2.0.0](https://github.com/dryvist/tofu-proxmox/compare/v1.92.0...v2.0.0) (2026-08-22)


### ⚠ BREAKING CHANGES

* **storage:** ansible_inventory no longer exposes host_services.

### Features

* **storage:** retire host_services in favour of per-dataset SMB shares ([#982](https://github.com/dryvist/tofu-proxmox/issues/982)) ([572dbc2](https://github.com/dryvist/tofu-proxmox/commit/572dbc2d590a9513fc9619a47d4226b54af7819a))

## [1.92.0](https://github.com/dryvist/tofu-proxmox/compare/v1.91.0...v1.92.0) (2026-08-22)


### Features

* **storage:** declare SMB shares on the datasets they serve ([#977](https://github.com/dryvist/tofu-proxmox/issues/977)) ([f14b13d](https://github.com/dryvist/tofu-proxmox/commit/f14b13dfb56098fd5c2a424ba6fda1bf0c92e9e7))

## [1.91.0](https://github.com/dryvist/tofu-proxmox/compare/v1.90.2...v1.91.0) (2026-08-21)


### Features

* **storage:** declare ZFS module params, pool properties, and vdev topology ([#972](https://github.com/dryvist/tofu-proxmox/issues/972)) ([3c82944](https://github.com/dryvist/tofu-proxmox/commit/3c82944ec27b2305ced7c243acab926209157fb6))

## [1.90.2](https://github.com/dryvist/tofu-proxmox/compare/v1.90.1...v1.90.2) (2026-08-16)


### Bug Fixes

* **serving:** correct concurrency-4 comment to a memory-budget justification ([#962](https://github.com/dryvist/tofu-proxmox/issues/962)) ([72f0632](https://github.com/dryvist/tofu-proxmox/commit/72f0632b8a1b5a52c2e4c4958b884f0237616367))
* **serving:** revert llm_concurrency to 2 ([#965](https://github.com/dryvist/tofu-proxmox/issues/965)) ([3e20e8c](https://github.com/dryvist/tofu-proxmox/commit/3e20e8c24e335d8ac4f328a36de47eeda60daf4d))

## [1.90.1](https://github.com/dryvist/tofu-proxmox/compare/v1.90.0...v1.90.1) (2026-08-16)


### Bug Fixes

* **ci:** derive the module test suite set and run it in pre-commit too ([#958](https://github.com/dryvist/tofu-proxmox/issues/958)) ([d77be96](https://github.com/dryvist/tofu-proxmox/commit/d77be967e91ad0d314fff94482d90ad880d59b01))
* **serving:** raise LLM serving concurrency ceiling to 4 ([#960](https://github.com/dryvist/tofu-proxmox/issues/960)) ([ffed119](https://github.com/dryvist/tofu-proxmox/commit/ffed119da55021a99d9c2405adb7ec071bf345af))

## [1.90.0](https://github.com/dryvist/tofu-proxmox/compare/v1.89.0...v1.90.0) (2026-08-15)


### Features

* **docling:** add a docling-serve guest for document extraction ([#951](https://github.com/dryvist/tofu-proxmox/issues/951)) ([7d737ec](https://github.com/dryvist/tofu-proxmox/commit/7d737ec795783d9120c1df9e94ab0e3df4e6f39d))
* **homarr:** add firewall, port constant and ingress route for a homarr guest ([#952](https://github.com/dryvist/tofu-proxmox/issues/952)) ([09e748e](https://github.com/dryvist/tofu-proxmox/commit/09e748e130808f5ee3575cbd6f3e7ebe634520aa))

## [1.89.0](https://github.com/dryvist/tofu-proxmox/compare/v1.88.0...v1.89.0) (2026-08-14)


### Features

* **iso:** serve install media from a configurable object prefix ([#941](https://github.com/dryvist/tofu-proxmox/issues/941)) ([9784431](https://github.com/dryvist/tofu-proxmox/commit/9784431749ec02ebfb49d0ff50e666dd16f19f3e))


### Bug Fixes

* **containers:** include volume mount points in backups by default ([#942](https://github.com/dryvist/tofu-proxmox/issues/942)) ([4dd5535](https://github.com/dryvist/tofu-proxmox/commit/4dd55354a60697e2e42547ec277e6870209b460d))

## [1.88.0](https://github.com/dryvist/tofu-proxmox/compare/v1.87.0...v1.88.0) (2026-08-14)


### Features

* **nodes:** publish a node's inventory-system device name ([#937](https://github.com/dryvist/tofu-proxmox/issues/937)) ([b86e7e7](https://github.com/dryvist/tofu-proxmox/commit/b86e7e76e9c7124bb577f22487e9345ad0e9f897))

## [1.87.0](https://github.com/dryvist/tofu-proxmox/compare/v1.86.2...v1.87.0) (2026-08-14)


### Features

* **inventory:** publish every guest's MAC, not only DHCP-first ones ([#931](https://github.com/dryvist/tofu-proxmox/issues/931)) ([f6f2ff3](https://github.com/dryvist/tofu-proxmox/commit/f6f2ff3ff62c888295015df22ad18147af56f465))

## [1.86.2](https://github.com/dryvist/tofu-proxmox/compare/v1.86.1...v1.86.2) (2026-08-12)


### Bug Fixes

* **inventory:** mark guest_domain nonsensitive to unblock ansible_inventory ([53442a1](https://github.com/dryvist/tofu-proxmox/commit/53442a15370abb7b8211675353dc943c36a18d72))
* **inventory:** mark guest_domain nonsensitive to unblock ansible_inventory ([07c2737](https://github.com/dryvist/tofu-proxmox/commit/07c27376c149536a71110d03219154e9d0c59652))

## [1.86.1](https://github.com/dryvist/tofu-proxmox/compare/v1.86.0...v1.86.1) (2026-08-11)


### Bug Fixes

* **dns:** publish DHCP-first guests under their VLAN's real DNS domain ([ff758d2](https://github.com/dryvist/tofu-proxmox/commit/ff758d2c456fe309e8e2ceba5c5392489d086cde))
* **dns:** publish DHCP-first guests under their VLAN's real DNS domain ([dd3f7a2](https://github.com/dryvist/tofu-proxmox/commit/dd3f7a2bf2da66af19eb43b9a6aaf7a7b2ed0c09))

## [1.86.0](https://github.com/dryvist/tofu-proxmox/compare/v1.85.1...v1.86.0) (2026-08-07)


### Features

* **vm:** let a guest declare that only an operator starts it ([#902](https://github.com/dryvist/tofu-proxmox/issues/902)) ([d98b7ec](https://github.com/dryvist/tofu-proxmox/commit/d98b7ec11ad454fb543e85ff9714e3a47c862bd9))

## [1.85.1](https://github.com/dryvist/tofu-proxmox/compare/v1.85.0...v1.85.1) (2026-08-07)


### Bug Fixes

* **iso:** drop the answer-ISO resource and import that block every plan ([#897](https://github.com/dryvist/tofu-proxmox/issues/897)) ([bfada62](https://github.com/dryvist/tofu-proxmox/commit/bfada62aea90a4afece842505e5af45a4c9e3ac0))

## [1.85.0](https://github.com/dryvist/tofu-proxmox/compare/v1.84.0...v1.85.0) (2026-08-07)


### Features

* **ai-log:** port allocation for seven AI Docker service log routes ([89ac886](https://github.com/dryvist/tofu-proxmox/commit/89ac886fe38f3d568433c809f126a20810b24f3c))

## [1.84.0](https://github.com/dryvist/tofu-proxmox/compare/v1.83.2...v1.84.0) (2026-08-06)


### Features

* **constants:** raise serving.llm_concurrency to 2 ([d795d44](https://github.com/dryvist/tofu-proxmox/commit/d795d44dc7d022a8adc12a4d5aabfc77122e319b))
* **constants:** raise serving.llm_concurrency to 2 ([3b396e7](https://github.com/dryvist/tofu-proxmox/commit/3b396e79aacea3f98da88d7c1df356142395a53b))

## [1.83.2](https://github.com/dryvist/tofu-proxmox/compare/v1.83.1...v1.83.2) (2026-08-06)


### Bug Fixes

* **infra:** explicit depends_on for iso downloads ([#880](https://github.com/dryvist/tofu-proxmox/issues/880)) ([b88e299](https://github.com/dryvist/tofu-proxmox/commit/b88e2994a995596f23a95dbe778a49b9c07fc6fd))

## [1.83.1](https://github.com/dryvist/tofu-proxmox/compare/v1.83.0...v1.83.1) (2026-08-05)


### Bug Fixes

* **vm:** handle null user_account gracefully for Windows VMs ([#871](https://github.com/dryvist/tofu-proxmox/issues/871)) ([a2c454c](https://github.com/dryvist/tofu-proxmox/commit/a2c454c203a6d9006f68b4e1c532dfead3a331e6))

## [1.83.0](https://github.com/dryvist/tofu-proxmox/compare/v1.82.0...v1.83.0) (2026-08-05)


### Features

* add Windows VM support and 3 VDI instances ([afd57da](https://github.com/dryvist/tofu-proxmox/commit/afd57da2464967c7cff0abf2d4ef35d300676d4f))
* add Windows VM support and VDI instances ([c32e95c](https://github.com/dryvist/tofu-proxmox/commit/c32e95c00283cdf68dd11fbf4d346d74710e5bbb))


### Bug Fixes

* **firewall:** move the OTLP ingest accept to the tier that terminates it ([#866](https://github.com/dryvist/tofu-proxmox/issues/866)) ([9e7b560](https://github.com/dryvist/tofu-proxmox/commit/9e7b5609ab8cbda231f68b111460a2418d05be3d))

## [1.82.0](https://github.com/dryvist/tofu-proxmox/compare/v1.81.0...v1.82.0) (2026-08-05)


### Features

* **imports:** adopt the untracked live Traefik ingress container ([6e25e5b](https://github.com/dryvist/tofu-proxmox/commit/6e25e5ba965f74895f4b37353b4dbb25f4e9f168))
* **imports:** populate node_services.traefik and import the running ingress guest ([ddf16e0](https://github.com/dryvist/tofu-proxmox/commit/ddf16e06a649c2ff8adbc1ded64755346e9d918c))

## [1.81.0](https://github.com/dryvist/tofu-proxmox/compare/v1.80.0...v1.81.0) (2026-08-04)


### Features

* **imports:** adopt the untracked live DNS container under its own identity ([26b6a75](https://github.com/dryvist/tofu-proxmox/commit/26b6a7505192ac0e1cd0dc34c8af1fbffe2720d7))

## [1.80.0](https://github.com/dryvist/tofu-proxmox/compare/v1.79.0...v1.80.0) (2026-08-04)


### Features

* **firewall:** allow outbound HTTPS from object-storage containers ([d139fb3](https://github.com/dryvist/tofu-proxmox/commit/d139fb3dd3cfcc7ae11a7952bb2e472a2cbf3fb2))
* **inventory:** publish the desired-state fingerprint into the artifact ([#856](https://github.com/dryvist/tofu-proxmox/issues/856)) ([b47efcd](https://github.com/dryvist/tofu-proxmox/commit/b47efcd538151feffd751175c38dd22afe81454b))

## [1.79.0](https://github.com/dryvist/tofu-proxmox/compare/v1.78.0...v1.79.0) (2026-08-04)


### Features

* **imports:** adopt relocated guests and resolve ids from the merged map ([#850](https://github.com/dryvist/tofu-proxmox/issues/850)) ([1e616e4](https://github.com/dryvist/tofu-proxmox/commit/1e616e4fc4dfa1635a593b3f40de0546ea00ad0b))

## [1.78.0](https://github.com/dryvist/tofu-proxmox/compare/v1.77.2...v1.78.0) (2026-08-03)


### Features

* **deployment:** add static file web host guest and SSO-gated route ([#845](https://github.com/dryvist/tofu-proxmox/issues/845)) ([973f5d7](https://github.com/dryvist/tofu-proxmox/commit/973f5d72065e2574f9a5a3564bad163c39eb983e))

## [1.77.2](https://github.com/dryvist/tofu-proxmox/compare/v1.77.1...v1.77.2) (2026-08-03)


### Bug Fixes

* adopt nautobot after an HA relocation ([#840](https://github.com/dryvist/tofu-proxmox/issues/840)) ([00b1d76](https://github.com/dryvist/tofu-proxmox/commit/00b1d768c915641d337d31fa53f66b4354f17cd9))

## [1.77.1](https://github.com/dryvist/tofu-proxmox/compare/v1.77.0...v1.77.1) (2026-08-03)


### Bug Fixes

* adopt the vikunja container into state ([#835](https://github.com/dryvist/tofu-proxmox/issues/835)) ([59a5314](https://github.com/dryvist/tofu-proxmox/commit/59a53143867db90f6d8e4aee26cdb0bff3752157))

## [1.77.0](https://github.com/dryvist/tofu-proxmox/compare/v1.76.8...v1.77.0) (2026-08-03)


### Features

* **constants:** publish the heavy-tier serving host identity ([#827](https://github.com/dryvist/tofu-proxmox/issues/827)) ([07812dd](https://github.com/dryvist/tofu-proxmox/commit/07812dd2600d4a0d5b6d79d7c548e1c62d6f2a12))
* **firewall:** admit the LLM router pool's shared spend store ([#829](https://github.com/dryvist/tofu-proxmox/issues/829)) ([9b9c3c9](https://github.com/dryvist/tofu-proxmox/commit/9b9c3c925ed16b6375f9bc7d1406d3dcc5efc977))

## [1.76.8](https://github.com/dryvist/tofu-proxmox/compare/v1.76.7...v1.76.8) (2026-08-02)


### Bug Fixes

* **ci:** guard ci-fix.yml against fork-origin workflow_run privilege escalation ([#822](https://github.com/dryvist/tofu-proxmox/issues/822)) ([2679c1b](https://github.com/dryvist/tofu-proxmox/commit/2679c1b2650882f7edf70fe8e58ea924f66c4d7b))

## [1.76.7](https://github.com/dryvist/tofu-proxmox/compare/v1.76.6...v1.76.7) (2026-08-02)


### Bug Fixes

* **constants:** add serving.llm_concurrency as the single source of truth ([#817](https://github.com/dryvist/tofu-proxmox/issues/817)) ([b9e5dda](https://github.com/dryvist/tofu-proxmox/commit/b9e5dda4b22839ca4d2dd6f9f65d2f07c8039fb9))

## [1.76.6](https://github.com/dryvist/tofu-proxmox/compare/v1.76.5...v1.76.6) (2026-07-31)


### Bug Fixes

* **state:** adopt nautobot and vikunja instead of planning failing creates ([#810](https://github.com/dryvist/tofu-proxmox/issues/810)) ([b7e4c2a](https://github.com/dryvist/tofu-proxmox/commit/b7e4c2aab694e980b16ca9b54d9f3b1222241a74))
* **vms:** let a node_name change migrate a VM instead of destroying it ([#812](https://github.com/dryvist/tofu-proxmox/issues/812)) ([0d726e5](https://github.com/dryvist/tofu-proxmox/commit/0d726e5a983100b509c5b31cb9e6692a27fdd9a1))

## [1.76.5](https://github.com/dryvist/tofu-proxmox/compare/v1.76.4...v1.76.5) (2026-07-31)


### Bug Fixes

* **checks:** convert both advisory check blocks to hard plan failures ([#802](https://github.com/dryvist/tofu-proxmox/issues/802)) ([794849b](https://github.com/dryvist/tofu-proxmox/commit/794849bda37a0758c5e24bb7f652dee34bd9a86d))

## [1.76.4](https://github.com/dryvist/tofu-proxmox/compare/v1.76.3...v1.76.4) (2026-07-31)


### Bug Fixes

* **addressing:** delete reserved_host — a lease is the only authority for a leased address ([#791](https://github.com/dryvist/tofu-proxmox/issues/791)) ([a89e66c](https://github.com/dryvist/tofu-proxmox/commit/a89e66cb1c8566eeb5dcf1218dfc52afa33497fc))
* **node-services:** fail the plan on a per_node key that names no known node ([#801](https://github.com/dryvist/tofu-proxmox/issues/801)) ([bdaf493](https://github.com/dryvist/tofu-proxmox/commit/bdaf493f3e991b96ad208cc963a4e5eda32a322d))
* **node-services:** stop emitting reserved_host — the schema no longer declares it ([#800](https://github.com/dryvist/tofu-proxmox/issues/800)) ([846348c](https://github.com/dryvist/tofu-proxmox/commit/846348c57d1faca71702dbc1201ae515badadef0))

## [1.76.3](https://github.com/dryvist/tofu-proxmox/compare/v1.76.2...v1.76.3) (2026-07-31)


### Bug Fixes

* **node-services:** emit one object shape, and the reserved_host dhcp requires ([#796](https://github.com/dryvist/tofu-proxmox/issues/796)) ([793867e](https://github.com/dryvist/tofu-proxmox/commit/793867e4c86a33d948b411d7544bb016212f27a2))
* **node-services:** honour the commissioned default so the generator is usable ([#794](https://github.com/dryvist/tofu-proxmox/issues/794)) ([1e21ce5](https://github.com/dryvist/tofu-proxmox/commit/1e21ce5160b4925e2843d88231b2363676bc26fb))

## [1.76.2](https://github.com/dryvist/tofu-proxmox/compare/v1.76.1...v1.76.2) (2026-07-30)


### Bug Fixes

* **openbao:** generate voters with a DHCP reservation, not a baked-in address ([#784](https://github.com/dryvist/tofu-proxmox/issues/784)) ([8ff414e](https://github.com/dryvist/tofu-proxmox/commit/8ff414e167aa543ac52805210c0b0fda618b6fcf))

## [1.76.1](https://github.com/dryvist/tofu-proxmox/compare/v1.76.0...v1.76.1) (2026-07-29)


### Bug Fixes

* **checks:** drop the storage-protection check, it contradicts stated policy ([#780](https://github.com/dryvist/tofu-proxmox/issues/780)) ([e098536](https://github.com/dryvist/tofu-proxmox/commit/e0985360889c39dba81ae6f6c13e5c93ce578296))

## [1.76.0](https://github.com/dryvist/tofu-proxmox/compare/v1.75.1...v1.76.0) (2026-07-29)


### Features

* **syslog:** add a hypervisor-health family instead of widening the os index ([6ea90e9](https://github.com/dryvist/tofu-proxmox/commit/6ea90e9605bee152fb75f1049c638a36a0815b65))
* **syslog:** add a hypervisor-health family instead of widening the os index ([0eea655](https://github.com/dryvist/tofu-proxmox/commit/0eea655d3e98c360a856de4637236b063c30f4f8))

## [1.75.1](https://github.com/dryvist/tofu-proxmox/compare/v1.75.0...v1.75.1) (2026-07-29)


### Bug Fixes

* **containers:** default LXC swap to the container's memory cap ([a6c3b70](https://github.com/dryvist/tofu-proxmox/commit/a6c3b700e94cc57a9a99633020595d02822444fb))
* **containers:** default LXC swap to the container's memory cap ([8127127](https://github.com/dryvist/tofu-proxmox/commit/8127127dfa08132cb5cfe07308b9727bcdaedaab))

## [1.75.0](https://github.com/dryvist/tofu-proxmox/compare/v1.74.0...v1.75.0) (2026-07-29)


### Features

* **firewall:** ai-proxied agent-pool profile behind a Squid egress chokepoint ([#753](https://github.com/dryvist/tofu-proxmox/issues/753)) ([6af9281](https://github.com/dryvist/tofu-proxmox/commit/6af92812ffb471c5f87ebf27bf948a1402c2a411))


### Bug Fixes

* **container:** ignore the whole user_account block, not just its attributes ([#756](https://github.com/dryvist/tofu-proxmox/issues/756)) ([bc7d500](https://github.com/dryvist/tofu-proxmox/commit/bc7d500da1b078c48883a56ea835e01dc6156999))

## [1.74.0](https://github.com/dryvist/tofu-proxmox/compare/v1.73.2...v1.74.0) (2026-07-27)


### Features

* **firewall:** add ai-github egress profile for headless AI runner ([#733](https://github.com/dryvist/tofu-proxmox/issues/733)) ([06a3084](https://github.com/dryvist/tofu-proxmox/commit/06a30848684cb117f8c9c4640202c215d6f11627))
* **firewall:** add ai-terrakube and ai-full-net egress profiles ([#735](https://github.com/dryvist/tofu-proxmox/issues/735)) ([ffa164b](https://github.com/dryvist/tofu-proxmox/commit/ffa164bfa58f25a71d56b332c4581a1a345e2ffc))
* **ingress:** add otel route fronting Cribl Stream OTLP trace ingest ([#743](https://github.com/dryvist/tofu-proxmox/issues/743)) ([cc018f6](https://github.com/dryvist/tofu-proxmox/commit/cc018f60663659dc5724ce1000a99f564706ac5c))
* **ingress:** add secure shared-host UI routes ([#729](https://github.com/dryvist/tofu-proxmox/issues/729)) ([a0c856b](https://github.com/dryvist/tofu-proxmox/commit/a0c856bc217562f6067b58a379a307e68b19ed39))
* **ingress:** SSO-gated Kanban board route for the Hermes task store ([#741](https://github.com/dryvist/tofu-proxmox/issues/741)) ([56f0c54](https://github.com/dryvist/tofu-proxmox/commit/56f0c5468db45d027eeadb0d65085c44b7f47c95))
* **main:** agentgateway MCP-fabric HA — second node_services consumer + pooled routes ([#738](https://github.com/dryvist/tofu-proxmox/issues/738)) ([e212543](https://github.com/dryvist/tofu-proxmox/commit/e2125431d96a0c75296ab5f3f196e893b499b09a))
* **main:** generic per-node (DaemonSet-style) service expansion, Traefik first consumer ([#737](https://github.com/dryvist/tofu-proxmox/issues/737)) ([ede93c1](https://github.com/dryvist/tofu-proxmox/commit/ede93c1d74ef3240245a4ea3c277cf5fb5d83491))
* **splunk:** declare Splunk-native HA cluster VMs ([#739](https://github.com/dryvist/tofu-proxmox/issues/739)) ([26d4572](https://github.com/dryvist/tofu-proxmox/commit/26d45721bbc26f6e745bd3a0f689a787793b56f8))


### Bug Fixes

* **firewall:** shorten ai-terrakube egress group name to Proxmox 18-char limit ([#736](https://github.com/dryvist/tofu-proxmox/issues/736)) ([9a1349d](https://github.com/dryvist/tofu-proxmox/commit/9a1349d4ad980d622ddf787e25262c4fc5250e15))
* **ingress:** address the OpenBao HA pool by FQDN, not a bare IP ([#748](https://github.com/dryvist/tofu-proxmox/issues/748)) ([e4b55b1](https://github.com/dryvist/tofu-proxmox/commit/e4b55b1954f0e99b5a17386df4062c9850a1eb71))
* **splunk:** disable block backup on fast-splunk tier, correct docs ([#744](https://github.com/dryvist/tofu-proxmox/issues/744)) ([8a3f221](https://github.com/dryvist/tofu-proxmox/commit/8a3f221d1acd4d0d0a666fad1f3d10903120ee80))

## [1.73.2](https://github.com/dryvist/tofu-proxmox/compare/v1.73.1...v1.73.2) (2026-07-20)


### Bug Fixes

* **startup:** derive guest boot order from VMID instead of startup_tier ([#720](https://github.com/dryvist/tofu-proxmox/issues/720)) ([fd4faac](https://github.com/dryvist/tofu-proxmox/commit/fd4faac0a097fff2859209de020f260ec484785b))
* **startup:** order guest boot by dependency tier, not VMID ([#719](https://github.com/dryvist/tofu-proxmox/issues/719)) ([f05e99d](https://github.com/dryvist/tofu-proxmox/commit/f05e99d7d62e362815e174041fb5015ec0048b6e))

## [1.73.1](https://github.com/dryvist/tofu-proxmox/compare/v1.73.0...v1.73.1) (2026-07-20)


### Bug Fixes

* **ci:** pass OPENAI_API_KEY through to the shared AI workflows ([#711](https://github.com/dryvist/tofu-proxmox/issues/711)) ([778cd66](https://github.com/dryvist/tofu-proxmox/commit/778cd66cc141bc519933f9bc7b7736323c16cb4c))

## [1.73.0](https://github.com/dryvist/tofu-proxmox/compare/v1.72.0...v1.73.0) (2026-07-20)


### Features

* **proxmox-stack:** route hermes agent logs to dedicated hermes index ([#705](https://github.com/dryvist/tofu-proxmox/issues/705)) ([ec201d8](https://github.com/dryvist/tofu-proxmox/commit/ec201d8fa5c2b90c9009668e1a6558e6b891ed93))

## [1.72.0](https://github.com/dryvist/tofu-proxmox/compare/v1.71.0...v1.72.0) (2026-07-20)


### Features

* **splunk:** declare fast-splunk/bulk-splunk storage tiers ([33cdfe3](https://github.com/dryvist/tofu-proxmox/commit/33cdfe3af71268aff414c3496e3b0ecfd9ff0c3e))


### Bug Fixes

* **dns:** derive resolver list from all technitium nodes, drop pi-hole ([#696](https://github.com/dryvist/tofu-proxmox/issues/696)) ([d104725](https://github.com/dryvist/tofu-proxmox/commit/d10472587e8d0b701289ec76a744a589ab4288e6))
* **openbao:** route ingress to the active peer only (drop standbyok) ([#700](https://github.com/dryvist/tofu-proxmox/issues/700)) ([80f6698](https://github.com/dryvist/tofu-proxmox/commit/80f6698f57b87bb1887833ff295086fb5fdfb21e))

## [1.71.0](https://github.com/dryvist/tofu-proxmox/compare/v1.70.0...v1.71.0) (2026-07-17)


### Features

* **container:** set guest DNS to the homelab resolvers, not the node's upstream ([#689](https://github.com/dryvist/tofu-proxmox/issues/689)) ([8d2464c](https://github.com/dryvist/tofu-proxmox/commit/8d2464c2e75c677b3f58f9fc02ecb77be5620771))

## [1.70.0](https://github.com/dryvist/tofu-proxmox/compare/v1.69.0...v1.70.0) (2026-07-17)


### Features

* **ssh:** retire the ansible-guest private-key copy (null_resource) ([#683](https://github.com/dryvist/tofu-proxmox/issues/683)) ([2e57d2a](https://github.com/dryvist/tofu-proxmox/commit/2e57d2a757458b4252ad09b888968667749f4721))


### Bug Fixes

* **ingress:** explicit sso flags on hindsight routes ([#680](https://github.com/dryvist/tofu-proxmox/issues/680)) ([9986c79](https://github.com/dryvist/tofu-proxmox/commit/9986c790d9f027412525d0011520063fa9a41d15))

## [1.69.0](https://github.com/dryvist/tofu-proxmox/compare/v1.68.1...v1.69.0) (2026-07-17)


### Features

* add Hindsight agent-memory service (constants, ingress pool, firewall) ([#675](https://github.com/dryvist/tofu-proxmox/issues/675)) ([70344b4](https://github.com/dryvist/tofu-proxmox/commit/70344b44b5d726d46ddd78805c68fa21d3bf2cb9))
* **ingress:** Authelia SSO guest, portal route, per-route sso gate flag ([#677](https://github.com/dryvist/tofu-proxmox/issues/677)) ([d70f851](https://github.com/dryvist/tofu-proxmox/commit/d70f85139d9d5c542c19d512d7834da0aab68fe2))

## [1.68.1](https://github.com/dryvist/tofu-proxmox/compare/v1.68.0...v1.68.1) (2026-07-16)


### Bug Fixes

* **vm:** clamp startup order at 0 for 6-digit VMIDs ([#668](https://github.com/dryvist/tofu-proxmox/issues/668)) ([2ecda6c](https://github.com/dryvist/tofu-proxmox/commit/2ecda6c7f48ca5f53bcf39b0d2f54e1c6d6ffc57))

## [1.68.0](https://github.com/dryvist/tofu-proxmox/compare/v1.67.2...v1.68.0) (2026-07-16)


### Features

* **deployment:** add apps-tier primary Postgres LXC (postgres-apps) ([#662](https://github.com/dryvist/tofu-proxmox/issues/662)) ([a76a4a0](https://github.com/dryvist/tofu-proxmox/commit/a76a4a087cac2049829693e20ff8c74d15dffdcd))
* **infra:** deploy Zammad in HA configuration and define multi-instance naming scheme ([46190a0](https://github.com/dryvist/tofu-proxmox/commit/46190a0c2693b2910b336850c9d7c618fce03bb9))

## [1.67.2](https://github.com/dryvist/tofu-proxmox/compare/v1.67.1...v1.67.2) (2026-07-14)


### Bug Fixes

* **vault:** set skip_child_token to true on vault providers ([#651](https://github.com/dryvist/tofu-proxmox/issues/651)) ([29c2d2d](https://github.com/dryvist/tofu-proxmox/commit/29c2d2d02e7cb5406336b7c81517c27768cb71c6))

## [1.67.1](https://github.com/dryvist/tofu-proxmox/compare/v1.67.0...v1.67.1) (2026-07-14)


### Bug Fixes

* add outbound_http rules to fix TLS connection hangs on Traefik backends ([a7ada6d](https://github.com/dryvist/tofu-proxmox/commit/a7ada6d33c957ba85e12124eb9f61c54134791cb))
* add outbound_http to fix Traefik backend timeouts ([238bb2e](https://github.com/dryvist/tofu-proxmox/commit/238bb2e9c1762ff26bc21fcd85ac2a092715ce0d))
* add outbound_https rule to vikunja firewall to prevent 504 timeout on OIDC requests ([8fe638b](https://github.com/dryvist/tofu-proxmox/commit/8fe638bff34ae86f7d7c8c183f7b314d4a0b4d45))

## [1.67.0](https://github.com/dryvist/tofu-proxmox/compare/v1.66.0...v1.67.0) (2026-07-13)


### Features

* **firewall:** allow OpenBao HTTPS egress ([#634](https://github.com/dryvist/tofu-proxmox/issues/634)) ([6238ce8](https://github.com/dryvist/tofu-proxmox/commit/6238ce819fed709637dc46eb30bda0220ae99e70))

## [1.66.0](https://github.com/dryvist/tofu-proxmox/compare/v1.65.1...v1.66.0) (2026-07-12)


### Features

* add zammad ITSM LXC shell (605020) with firewall + ingress ([5d88f2f](https://github.com/dryvist/tofu-proxmox/commit/5d88f2f3083fe2550da1f77427f6b4314aff95a3))
* add zammad ITSM LXC shell (605020) with firewall + ingress ([c53a3e5](https://github.com/dryvist/tofu-proxmox/commit/c53a3e5b0d0e963e03b828d7e5d8e54e46960950))
* **agentgateway:** split metrics port (15020) + mcp ingress front door ([#620](https://github.com/dryvist/tofu-proxmox/issues/620)) ([536d582](https://github.com/dryvist/tofu-proxmox/commit/536d582ad0682e596d206fe9fbb6cf6bf900e085))
* **constants:** llm_night_api port for the night-cluster endpoint ([24b8d45](https://github.com/dryvist/tofu-proxmox/commit/24b8d457b2b93c6d46055e0581aeeb96f19efaa7))
* enable entire session capture (local-only) ([#616](https://github.com/dryvist/tofu-proxmox/issues/616)) ([ca01ba3](https://github.com/dryvist/tofu-proxmox/commit/ca01ba377fc0f48b2f4851448fc1d0c9dfd83ce7))
* **hermes:** inbound webhook port, firewall SG, and Traefik ingress ([#626](https://github.com/dryvist/tofu-proxmox/issues/626)) ([1e4640f](https://github.com/dryvist/tofu-proxmox/commit/1e4640f1fb1889da49bbfe758ca2a7f2aec8f077))
* **hermes:** job-submission API port, firewall rule, and Traefik ingress ([#627](https://github.com/dryvist/tofu-proxmox/issues/627)) ([76729f0](https://github.com/dryvist/tofu-proxmox/commit/76729f0d4c080d57c57e1c8ec590019739078f05))
* **nautobot:** wire Nautobot + shared Postgres guests and stamp inventory schema_version ([#617](https://github.com/dryvist/tofu-proxmox/issues/617)) ([5d2d6c0](https://github.com/dryvist/tofu-proxmox/commit/5d2d6c05162d062bb5361b65541c9253b1ba8442))
* **vault-secrets:** seed secret/apps/zammad via apps-seed AppRole ([9a2988a](https://github.com/dryvist/tofu-proxmox/commit/9a2988a44bcd4f0ce6d308c2bbc806e658f85dab))
* **vault-secrets:** seed secret/apps/zammad via apps-seed AppRole ([36be890](https://github.com/dryvist/tofu-proxmox/commit/36be89089d6e9fd92c80e1bc6965e7c05f2e2ea6))
* **vikunja:** wire vikunja LXC firewall, ingress, and service port ([#619](https://github.com/dryvist/tofu-proxmox/issues/619)) ([2b8141e](https://github.com/dryvist/tofu-proxmox/commit/2b8141eb434fdfa474e6e66eb8da9c76eb4a0639))


### Bug Fixes

* keep firewall test + main.tf green for zammad addition ([0eb3981](https://github.com/dryvist/tofu-proxmox/commit/0eb398120895dd19ae83d88aeb54f4a0d9dd9bb0))
* **vault-secrets:** skip child token for least-privilege AppRole ([408d17a](https://github.com/dryvist/tofu-proxmox/commit/408d17a7699837153161548e0e06358d289ea3c5))
* **vault-secrets:** skip child token for least-privilege AppRole ([02d1b2e](https://github.com/dryvist/tofu-proxmox/commit/02d1b2e7b1ccf95306e70adaa59c268dc739aefb)), closes [#138](https://github.com/dryvist/tofu-proxmox/issues/138)
* **vault-secrets:** vault provider 5.10 compat and postgres tag scope ([b23b7cd](https://github.com/dryvist/tofu-proxmox/commit/b23b7cd72b1693f1228bfd62b4679dc03a50ab8f))

## [1.65.1](https://github.com/dryvist/terraform-proxmox/compare/v1.65.0...v1.65.1) (2026-07-08)


### Bug Fixes

* **firewall:** attach ai-log-ingest accepts to the Cribl Stream backends ([#597](https://github.com/dryvist/terraform-proxmox/issues/597)) ([bdb145b](https://github.com/dryvist/terraform-proxmox/commit/bdb145b4ce37ae3313aade62e5f02deb81466b72))

## [1.65.0](https://github.com/dryvist/terraform-proxmox/compare/v1.64.0...v1.65.0) (2026-07-08)


### Features

* **network:** media tier to VLAN 70 — complete the VMID/VLAN tier alignment ([#595](https://github.com/dryvist/terraform-proxmox/issues/595)) ([a3a5e19](https://github.com/dryvist/terraform-proxmox/commit/a3a5e194b0460293593578e3fa7961e3671090d1))

## [1.64.0](https://github.com/dryvist/terraform-proxmox/compare/v1.63.0...v1.64.0) (2026-07-08)


### Features

* **firewall:** DROP/DROP guest companions for the LAN-only media tier ([#592](https://github.com/dryvist/terraform-proxmox/issues/592)) ([770b075](https://github.com/dryvist/terraform-proxmox/commit/770b075f1c9c1d655fd5657e09f39fc68d8038b4))

## [1.63.0](https://github.com/dryvist/terraform-proxmox/compare/v1.62.0...v1.63.0) (2026-07-07)


### Features

* **firewall:** dual pipeline+siem zero-trust sources for the VLAN-40 rebuild ([#583](https://github.com/dryvist/terraform-proxmox/issues/583)) ([4ef5fe8](https://github.com/dryvist/terraform-proxmox/commit/4ef5fe8a0dccdf7321109a817063109527f05967))
* **firewall:** siem-scoped node_exporter scrape rule on the Proxmox hosts ([#585](https://github.com/dryvist/terraform-proxmox/issues/585)) ([2b7c9a4](https://github.com/dryvist/terraform-proxmox/commit/2b7c9a4d416bb417bbafefa7046b6d3d05485eb6))

## [1.62.0](https://github.com/dryvist/terraform-proxmox/compare/v1.61.1...v1.62.0) (2026-07-07)


### Features

* **constants:** ai_log_routing map — per-source index/sourcetype truth ([#584](https://github.com/dryvist/terraform-proxmox/issues/584)) ([1835b69](https://github.com/dryvist/terraform-proxmox/commit/1835b69b565081459b2abae05a60f5a93cb056b6)), closes [#579](https://github.com/dryvist/terraform-proxmox/issues/579)

## [1.61.1](https://github.com/dryvist/terraform-proxmox/compare/v1.61.0...v1.61.1) (2026-07-07)


### Bug Fixes

* **tests:** repair firewall module test suite and gate it in CI ([#582](https://github.com/dryvist/terraform-proxmox/issues/582)) ([576afe0](https://github.com/dryvist/terraform-proxmox/commit/576afe0725d8b092d7f85ee532fd81f81487a9c8)), closes [#580](https://github.com/dryvist/terraform-proxmox/issues/580)

## [1.61.0](https://github.com/dryvist/terraform-proxmox/compare/v1.60.0...v1.61.0) (2026-07-07)


### Features

* **telemetry:** per-source Cribl ports + universal logging firewall rules ([#578](https://github.com/dryvist/terraform-proxmox/issues/578)) ([af5d7a4](https://github.com/dryvist/terraform-proxmox/commit/af5d7a40ef753d6b1aeded00d6a4636599de6513))

## [1.60.0](https://github.com/dryvist/terraform-proxmox/compare/v1.59.0...v1.60.0) (2026-07-07)


### Features

* **ai:** add n8n + LangGraph to the AI orchestration tier ([#575](https://github.com/dryvist/terraform-proxmox/issues/575)) ([cc7582b](https://github.com/dryvist/terraform-proxmox/commit/cc7582b46f12f19ed698af52caa2f8a53b740f7d))

## [1.59.0](https://github.com/dryvist/terraform-proxmox/compare/v1.58.0...v1.59.0) (2026-07-06)


### Features

* **aws-infra:** gate pve public A record off by default (split-horizon DNS) ([#572](https://github.com/dryvist/terraform-proxmox/issues/572)) ([1112df1](https://github.com/dryvist/terraform-proxmox/commit/1112df1bf43a5f6f1029de4849941c5fdac8b559))

## [1.58.0](https://github.com/dryvist/terraform-proxmox/compare/v1.57.1...v1.58.0) (2026-07-06)


### Features

* **dr:** ingress VRRP HA + deployment.json S3 fetch failover ([#570](https://github.com/dryvist/terraform-proxmox/issues/570)) ([980d5cc](https://github.com/dryvist/terraform-proxmox/commit/980d5cc8186ca8ba72b16910162f7cccf8c01420))

## [1.57.1](https://github.com/dryvist/terraform-proxmox/compare/v1.57.0...v1.57.1) (2026-07-06)


### Bug Fixes

* **firewall:** allow DHCP on hermes-agent so it leases behind DROP ([#568](https://github.com/dryvist/terraform-proxmox/issues/568)) ([9db0404](https://github.com/dryvist/terraform-proxmox/commit/9db04041fd00f25e4ab8de527222d852501ec963))

## [1.57.0](https://github.com/dryvist/terraform-proxmox/compare/v1.56.1...v1.57.0) (2026-07-06)


### Features

* **firewall:** stage zero-trust rule scoping (disabled) ([0d58b03](https://github.com/dryvist/terraform-proxmox/commit/0d58b03f448974efac1bf80e36562dedf07caf26))

## [1.56.1](https://github.com/dryvist/terraform-proxmox/compare/v1.56.0...v1.56.1) (2026-07-05)


### Bug Fixes

* **aws-infra:** add missing Route53 A record for jevans-ms ([#559](https://github.com/dryvist/terraform-proxmox/issues/559)) ([7c8815a](https://github.com/dryvist/terraform-proxmox/commit/7c8815a82e6f34a46112e2e3a2454fbb08a1625c))

## [1.56.0](https://github.com/dryvist/terraform-proxmox/compare/v1.55.1...v1.56.0) (2026-07-05)


### Features

* **containers:** add agentgateway MCP/LLM/A2A data-plane proxy ([#562](https://github.com/dryvist/terraform-proxmox/issues/562)) ([2f3f617](https://github.com/dryvist/terraform-proxmox/commit/2f3f617f36bbcd5f396ff04e4992022a786f3ce2))

## [1.55.1](https://github.com/dryvist/terraform-proxmox/compare/v1.55.0...v1.55.1) (2026-07-05)


### Bug Fixes

* **ci:** mask *arr secrets and use heredoc GITHUB_ENV writes in drift workflow ([#557](https://github.com/dryvist/terraform-proxmox/issues/557)) ([7528d95](https://github.com/dryvist/terraform-proxmox/commit/7528d954507dac3a593dc8b9b7b6ac07d5020215))

## [1.55.0](https://github.com/dryvist/terraform-proxmox/compare/v1.54.0...v1.55.0) (2026-07-05)


### Features

* **aws-infra:** env-driven service-alias CNAMEs in the public zone ([#555](https://github.com/dryvist/terraform-proxmox/issues/555)) ([75e2c09](https://github.com/dryvist/terraform-proxmox/commit/75e2c09d2fe935babab34b743cac2aab43f8851c))

## [1.54.0](https://github.com/dryvist/terraform-proxmox/compare/v1.53.0...v1.54.0) (2026-07-05)


### Features

* **media:** add Sortarr insights dashboard to ingress + port constants ([#553](https://github.com/dryvist/terraform-proxmox/issues/553)) ([f2b07cc](https://github.com/dryvist/terraform-proxmox/commit/f2b07cc53a1d7768f147e33bdca9bee9a1cadaac))

## [1.53.0](https://github.com/dryvist/terraform-proxmox/compare/v1.52.1...v1.53.0) (2026-07-05)


### Features

* **ingress:** front Splunk HEC at splunk-hec.&lt;domain&gt; on the TLS entrypoint ([#550](https://github.com/dryvist/terraform-proxmox/issues/550)) ([7350f28](https://github.com/dryvist/terraform-proxmox/commit/7350f285d20e6d891c1b456dcc7dbd43a60f2ab6))

## [1.52.1](https://github.com/dryvist/terraform-proxmox/compare/v1.52.0...v1.52.1) (2026-07-05)


### Bug Fixes

* **vm:** ignore clone block changes to avoid ForceNew on re-import ([#548](https://github.com/dryvist/terraform-proxmox/issues/548)) ([394f96e](https://github.com/dryvist/terraform-proxmox/commit/394f96e9db3f9a9aa919a00230d1cd8c0de56c0c))

## [1.52.0](https://github.com/dryvist/terraform-proxmox/compare/v1.51.0...v1.52.0) (2026-07-04)


### Features

* enable issues:labeled trigger to close the auto-resolve loop ([#543](https://github.com/dryvist/terraform-proxmox/issues/543)) ([91aa2db](https://github.com/dryvist/terraform-proxmox/commit/91aa2db28b653bf6f9eeaa1581948a295f12efe6))

## [1.51.0](https://github.com/dryvist/terraform-proxmox/compare/v1.50.4...v1.51.0) (2026-07-04)


### Features

* **ingress:** LiteLLM router pool at llm.&lt;domain&gt;; chat route; drop dead entries ([#540](https://github.com/dryvist/terraform-proxmox/issues/540)) ([40ccd8c](https://github.com/dryvist/terraform-proxmox/commit/40ccd8c8754f6eda156223d5056f2c1dc5401e57))

## [1.50.4](https://github.com/dryvist/terraform-proxmox/compare/v1.50.3...v1.50.4) (2026-07-04)


### Bug Fixes

* **firewall:** outbound HTTPS for vectordb + rag containers ([#538](https://github.com/dryvist/terraform-proxmox/issues/538)) ([f127c4f](https://github.com/dryvist/terraform-proxmox/commit/f127c4f2a946e31b57caf3924abc460330df6a58))

## [1.50.3](https://github.com/dryvist/terraform-proxmox/compare/v1.50.2...v1.50.3) (2026-07-04)


### Bug Fixes

* **inventory:** allow non-apex pooled ingress in publish precondition ([#535](https://github.com/dryvist/terraform-proxmox/issues/535)) ([cdabb58](https://github.com/dryvist/terraform-proxmox/commit/cdabb58cf5d9f53b6f9c169cba3c2c346ec0c74a))

## [1.50.2](https://github.com/dryvist/terraform-proxmox/compare/v1.50.1...v1.50.2) (2026-07-04)


### Bug Fixes

* **firewall:** allow DHCP on vectordb + rag container options ([#533](https://github.com/dryvist/terraform-proxmox/issues/533)) ([4501af6](https://github.com/dryvist/terraform-proxmox/commit/4501af608fa39bfcd2c24c1d64e01253255d62e3))

## [1.50.1](https://github.com/dryvist/terraform-proxmox/compare/v1.50.0...v1.50.1) (2026-07-04)


### Bug Fixes

* **ingress:** match OpenBao backend pool keys to deployment container keys ([#531](https://github.com/dryvist/terraform-proxmox/issues/531)) ([5360f57](https://github.com/dryvist/terraform-proxmox/commit/5360f57a70507a3a450894b3fafa4125ca62f935))

## [1.50.0](https://github.com/dryvist/terraform-proxmox/compare/v1.49.0...v1.50.0) (2026-07-04)


### Features

* **ingress:** front IaC automation platform + RustFS S3 API by FQDN ([#523](https://github.com/dryvist/terraform-proxmox/issues/523)) ([2c5cb00](https://github.com/dryvist/terraform-proxmox/commit/2c5cb000a3fcc9c8bd7487b77fbf2ebaa3a90416))

## [1.49.0](https://github.com/dryvist/terraform-proxmox/compare/v1.48.0...v1.49.0) (2026-07-03)


### Features

* add LLM fabric foundation (VLAN end-state, llm-fast/router ports, firewall) ([#524](https://github.com/dryvist/terraform-proxmox/issues/524)) ([b94c5a3](https://github.com/dryvist/terraform-proxmox/commit/b94c5a31d0d4c014ef0d87481a9049cf208654c6))

## [1.48.0](https://github.com/dryvist/terraform-proxmox/compare/v1.47.2...v1.48.0) (2026-07-03)


### Features

* add AI PR care caller (dep review + release highlights) ([#519](https://github.com/dryvist/terraform-proxmox/issues/519)) ([003eedf](https://github.com/dryvist/terraform-proxmox/commit/003eedf5b235a33d243c2b7eb242feafee7c7466))

## [1.47.2](https://github.com/dryvist/terraform-proxmox/compare/v1.47.1...v1.47.2) (2026-07-02)


### Bug Fixes

* point callers at renamed cc- reusable workflows ([245a592](https://github.com/dryvist/terraform-proxmox/commit/245a59237b0f45f61783317eea0f7db17556b03f))

## [1.47.1](https://github.com/dryvist/terraform-proxmox/compare/v1.47.0...v1.47.1) (2026-07-02)


### Bug Fixes

* **firewall:** honeypot notify security-group name under 18-char cap ([e7d5aae](https://github.com/dryvist/terraform-proxmox/commit/e7d5aaef11a8be8ac5d9acc16b9e808a209df8c9))

## [1.47.0](https://github.com/dryvist/terraform-proxmox/compare/v1.46.3...v1.47.0) (2026-07-01)


### Features

* **honeypots:** network-wide deception fabric with instant phone alerting ([#491](https://github.com/dryvist/terraform-proxmox/issues/491)) ([39a8598](https://github.com/dryvist/terraform-proxmox/commit/39a8598475c0d1e3184dce6a0909075895563bb5))

## [1.46.3](https://github.com/dryvist/terraform-proxmox/compare/v1.46.2...v1.46.3) (2026-06-30)


### Bug Fixes

* **proxmox:** unblock the AI-orchestration tier apply (docker features + firewall group name) ([#508](https://github.com/dryvist/terraform-proxmox/issues/508)) ([f4788e2](https://github.com/dryvist/terraform-proxmox/commit/f4788e2bf892a34c0f8e6a66b58282e9125b77b3))

## [1.46.2](https://github.com/dryvist/terraform-proxmox/compare/v1.46.1...v1.46.2) (2026-06-29)


### Bug Fixes

* **containers:** ignore out-of-band idmap drift to protect media ([#505](https://github.com/dryvist/terraform-proxmox/issues/505)) ([692b23d](https://github.com/dryvist/terraform-proxmox/commit/692b23d20ec548cfc9e7b9e812ff5e65b7b19783))

## [1.46.1](https://github.com/dryvist/terraform-proxmox/compare/v1.46.0...v1.46.1) (2026-06-29)


### Bug Fixes

* **ci:** repair and enable the ci-fix wrapper ([#502](https://github.com/dryvist/terraform-proxmox/issues/502)) ([0ee7e0d](https://github.com/dryvist/terraform-proxmox/commit/0ee7e0dbf4b50d5ff58e76d74b85ef472aa049b5))

## [1.46.0](https://github.com/dryvist/terraform-proxmox/compare/v1.45.0...v1.46.0) (2026-06-27)


### Features

* **ai:** firewall + ports + ingress for AI orchestration stack ([#494](https://github.com/dryvist/terraform-proxmox/issues/494)) ([abbaa0c](https://github.com/dryvist/terraform-proxmox/commit/abbaa0c2606c3d3f246f3d163b15c19ad0aae2ab))

## [1.45.0](https://github.com/dryvist/terraform-proxmox/compare/v1.44.0...v1.45.0) (2026-06-27)


### Features

* **openbao:** on-prem static-key unseal + HA ingress + secret hierarchy ([#496](https://github.com/dryvist/terraform-proxmox/issues/496)) ([a740a84](https://github.com/dryvist/terraform-proxmox/commit/a740a8490c0d3737244ab4ed576d4d25d768c8e0))

## [1.44.0](https://github.com/dryvist/terraform-proxmox/compare/v1.43.1...v1.44.0) (2026-06-24)


### Features

* **inventory:** deployment.json desired-state from a private s3 store (fail-loud) ([#489](https://github.com/dryvist/terraform-proxmox/issues/489)) ([c239c12](https://github.com/dryvist/terraform-proxmox/commit/c239c12d8cef8bef796b7ac6bd1236a4329190b7))


### Bug Fixes

* **firewall:** allow DHCP on the object-storage container ([#490](https://github.com/dryvist/terraform-proxmox/issues/490)) ([dba2519](https://github.com/dryvist/terraform-proxmox/commit/dba25196fc0d1869685ae3e1a2ef4672b4b7bfd1))

## [1.43.1](https://github.com/dryvist/terraform-proxmox/compare/v1.43.0...v1.43.1) (2026-06-22)


### Bug Fixes

* use generic DOPPLER_TOKEN secret, drop vault-specific names ([#482](https://github.com/dryvist/terraform-proxmox/issues/482)) ([cd3a8d0](https://github.com/dryvist/terraform-proxmox/commit/cd3a8d0fd27280b2e36af6469cdc059dc121a1d3))

## [1.43.0](https://github.com/dryvist/terraform-proxmox/compare/v1.42.0...v1.43.0) (2026-06-22)


### Features

* **firewall:** add hermes-agent egress group for the autonomous agent LXC ([#484](https://github.com/dryvist/terraform-proxmox/issues/484)) ([e4485c0](https://github.com/dryvist/terraform-proxmox/commit/e4485c0894fc59a0c57eddb1fd74ebd3c6c5e1c2))

## [1.42.0](https://github.com/dryvist/terraform-proxmox/compare/v1.41.0...v1.42.0) (2026-06-22)


### Features

* **ingress:** front Splunk management API (8089) at splunk-mgmt ([#485](https://github.com/dryvist/terraform-proxmox/issues/485)) ([6ca9145](https://github.com/dryvist/terraform-proxmox/commit/6ca9145c90cd2600d5b1a590762b8fa999d892ff))

## [1.41.0](https://github.com/dryvist/terraform-proxmox/compare/v1.40.1...v1.41.0) (2026-06-21)


### Features

* **ci:** dispatch downstream revalidation on release ([#479](https://github.com/dryvist/terraform-proxmox/issues/479)) ([ee9322d](https://github.com/dryvist/terraform-proxmox/commit/ee9322d2f58e070a714e937ec6e31f45a8088927))

## [1.40.1](https://github.com/dryvist/terraform-proxmox/compare/v1.40.0...v1.40.1) (2026-06-20)


### Bug Fixes

* **docs:** rename netmon metric index to netmon_metrics ([#477](https://github.com/dryvist/terraform-proxmox/issues/477)) ([7ec6a15](https://github.com/dryvist/terraform-proxmox/commit/7ec6a153a44391efeee8c0f8f6e341bb9e57c0a6))

## [1.40.0](https://github.com/dryvist/terraform-proxmox/compare/v1.39.0...v1.40.0) (2026-06-19)


### Features

* **object-storage:** add RustFS LXC alongside MinIO for migration ([#472](https://github.com/dryvist/terraform-proxmox/issues/472)) ([d58116e](https://github.com/dryvist/terraform-proxmox/commit/d58116ef6ef4cc4e358ae38fc347e1f6d2fe998a))

## [1.39.0](https://github.com/dryvist/terraform-proxmox/compare/v1.38.2...v1.39.0) (2026-06-19)


### Features

* **servarr-config:** scheduled tofu-plan drift detection on self-hosted runner ([#471](https://github.com/dryvist/terraform-proxmox/issues/471)) ([50ab314](https://github.com/dryvist/terraform-proxmox/commit/50ab314065fd744ac10405a4cc021ff08ea9b2e8))

## [1.38.2](https://github.com/dryvist/terraform-proxmox/compare/v1.38.1...v1.38.2) (2026-06-17)


### Bug Fixes

* **firewall:** open TCP 9201 on cribl_stream containers for prometheus_rw ([#465](https://github.com/dryvist/terraform-proxmox/issues/465)) ([52bc357](https://github.com/dryvist/terraform-proxmox/commit/52bc3574ced96f99f5be0292656ecbf14dbe12b4))

## [1.38.1](https://github.com/dryvist/terraform-proxmox/compare/v1.38.0...v1.38.1) (2026-06-16)


### Bug Fixes

* **ingress:** drop the dead pi-hole route (no Pi-hole app on that backend) ([#463](https://github.com/dryvist/terraform-proxmox/issues/463)) ([e7e2cfc](https://github.com/dryvist/terraform-proxmox/commit/e7e2cfcd3a9a483d4d235513f1c516282a95c8e9))

## [1.38.0](https://github.com/dryvist/terraform-proxmox/compare/v1.37.0...v1.38.0) (2026-06-15)


### Features

* **storage:** document the appdata dataset for persistent app config ([9b3c1da](https://github.com/dryvist/terraform-proxmox/commit/9b3c1dace8d52318d1a3a359131bc22f7dfd6c01))

## [1.37.0](https://github.com/dryvist/terraform-proxmox/compare/v1.36.0...v1.37.0) (2026-06-15)


### Features

* **object-storage:** add RustFS object-storage LXC alongside MinIO for migration ([#456](https://github.com/dryvist/terraform-proxmox/issues/456)) ([1743a52](https://github.com/dryvist/terraform-proxmox/commit/1743a523f4a232bc33423de80cc0d4d363c38fcf))
* **proxmox-container:** derive Docker-in-LXC features from the docker tag ([#457](https://github.com/dryvist/terraform-proxmox/issues/457)) ([75db4a4](https://github.com/dryvist/terraform-proxmox/commit/75db4a472f68e3900fbb35aa05bb8eaf7bd2a3e6))

## [1.36.0](https://github.com/dryvist/terraform-proxmox/compare/v1.35.1...v1.36.0) (2026-06-14)


### Features

* **inventory:** gate the S3 publish on a precondition, fail before writing garbage ([3f0e2c9](https://github.com/dryvist/terraform-proxmox/commit/3f0e2c976184ff943758a48ce0706cb6241feb56))

## [1.35.1](https://github.com/dryvist/terraform-proxmox/compare/v1.35.0...v1.35.1) (2026-06-14)


### Bug Fixes

* **servarr-config:** align committed config to adopted live state ([#451](https://github.com/dryvist/terraform-proxmox/issues/451)) ([1497d55](https://github.com/dryvist/terraform-proxmox/commit/1497d5594537a7dc9a5481160784f978db316ce4))

## [1.35.0](https://github.com/dryvist/terraform-proxmox/compare/v1.34.1...v1.35.0) (2026-06-14)


### Features

* **servarr-config:** declarative Sonarr/Radarr config via devopsarr ([#448](https://github.com/dryvist/terraform-proxmox/issues/448)) ([d2352a7](https://github.com/dryvist/terraform-proxmox/commit/d2352a753b80da8fb8582b722ab59ff75ec1e84f))

## [1.34.1](https://github.com/dryvist/terraform-proxmox/compare/v1.34.0...v1.34.1) (2026-06-14)


### Bug Fixes

* **locals:** support static-IP exception hosts with positional VMIDs ([a6cceea](https://github.com/dryvist/terraform-proxmox/commit/a6cceeaa09c757ac037e0dd9f5438095e15e9004))

## [1.34.0](https://github.com/dryvist/terraform-proxmox/compare/v1.33.2...v1.34.0) (2026-06-14)


### Features

* **containers:** document unifi-metrics LXC for UniFi telemetry collector ([#440](https://github.com/dryvist/terraform-proxmox/issues/440)) ([ab33469](https://github.com/dryvist/terraform-proxmox/commit/ab334695e8c5146332ed71f2dace95bfbb473ce9))

## [1.33.2](https://github.com/dryvist/terraform-proxmox/compare/v1.33.1...v1.33.2) (2026-06-14)


### Bug Fixes

* **container:** ignore mount_point drift so applies don't replace media LXCs ([#439](https://github.com/dryvist/terraform-proxmox/issues/439)) ([f722f54](https://github.com/dryvist/terraform-proxmox/commit/f722f5434e4e62f7b9097de03fdd785684799a53))

## [1.33.1](https://github.com/dryvist/terraform-proxmox/compare/v1.33.0...v1.33.1) (2026-06-12)


### Bug Fixes

* **ci:** repoint shared reusable workflows to dryvist org ([#436](https://github.com/dryvist/terraform-proxmox/issues/436)) ([272eb26](https://github.com/dryvist/terraform-proxmox/commit/272eb264ef8462095e0e8f2225ec474021759388))

## [1.33.0](https://github.com/dryvist/terraform-proxmox/compare/v1.32.0...v1.33.0) (2026-06-12)


### Features

* **containers:** deterministic MAC + reserved-IP contract for DHCP-first guests ([#430](https://github.com/dryvist/terraform-proxmox/issues/430)) ([9103512](https://github.com/dryvist/terraform-proxmox/commit/91035129dab73e2a01eddfce25a19c694118db8f))
* **firewall:** cribl_s2s port 10300 for remote Edge -&gt; HAProxy -&gt; Stream ([#424](https://github.com/dryvist/terraform-proxmox/issues/424)) ([93bb34f](https://github.com/dryvist/terraform-proxmox/commit/93bb34f3d5962739ee1a06cb90b47e7e5247be63))
* **storage:** document the databases dataset shape in deployment.json.example ([#426](https://github.com/dryvist/terraform-proxmox/issues/426)) ([10472ce](https://github.com/dryvist/terraform-proxmox/commit/10472cec6ae10b4ebe828ab62c401966089efd88))


### Bug Fixes

* **splunk:** deploy natively — drop dead :10.0.2 compose, pre-own /opt/splunk as 41812 ([#425](https://github.com/dryvist/terraform-proxmox/issues/425)) ([4fd485d](https://github.com/dryvist/terraform-proxmox/commit/4fd485d871dc4283c86836ed07420e3a58e261bb))
* **sync:** env-driven sync destination; detect untracked changes; PR-based commit flow ([#428](https://github.com/dryvist/terraform-proxmox/issues/428)) ([f7bcae1](https://github.com/dryvist/terraform-proxmox/commit/f7bcae140054149aa0e94426c3b001100b3a06e6))
* **terragrunt:** wait on held state locks instead of failing (-lock-timeout=10m) ([#431](https://github.com/dryvist/terraform-proxmox/issues/431)) ([3e819ee](https://github.com/dryvist/terraform-proxmox/commit/3e819eef7f214d764f64f543bd5d8a68463f6f33))
* **vm:** ignore cloud-init dns drift to avoid rebuilding the non-removable ide2 drive ([#432](https://github.com/dryvist/terraform-proxmox/issues/432)) ([e888eb7](https://github.com/dryvist/terraform-proxmox/commit/e888eb7b5127ac98c435af710f70fd6c01a0c7df))

## [1.32.0](https://github.com/dryvist/terraform-proxmox/compare/v1.31.0...v1.32.0) (2026-06-11)


### Features

* **vm:** explicit guest DNS servers derived from the DNS containers ([#419](https://github.com/dryvist/terraform-proxmox/issues/419)) ([2979bee](https://github.com/dryvist/terraform-proxmox/commit/2979beef2e3c9be4058c94f00a3e864d52d16521))

## [1.31.0](https://github.com/dryvist/terraform-proxmox/compare/v1.30.2...v1.31.0) (2026-06-11)


### Features

* **pipeline:** single-source syslog port map + standard-frontend firewall + Cribl telemetry egress ([#416](https://github.com/dryvist/terraform-proxmox/issues/416)) ([f9ed855](https://github.com/dryvist/terraform-proxmox/commit/f9ed855eb636107764f09945696d27c8f5ec4f95))

## [1.30.2](https://github.com/dryvist/terraform-proxmox/compare/v1.30.1...v1.30.2) (2026-06-10)


### Bug Fixes

* **ci:** grant actions:read to retrigger-pr-checks caller ([#414](https://github.com/dryvist/terraform-proxmox/issues/414)) ([5e9658d](https://github.com/dryvist/terraform-proxmox/commit/5e9658dbe58a8f2e07bb4985cd5c0901b464e365))

## [1.30.1](https://github.com/dryvist/terraform-proxmox/compare/v1.30.0...v1.30.1) (2026-06-10)


### Bug Fixes

* **firewall:** allow inbound HEC on cribl_edge for netmon probers ([#411](https://github.com/dryvist/terraform-proxmox/issues/411)) ([9f1bf31](https://github.com/dryvist/terraform-proxmox/commit/9f1bf31a7a89761c38c7594f915358378cc6593e))

## [1.30.0](https://github.com/dryvist/terraform-proxmox/compare/v1.29.0...v1.30.0) (2026-06-10)


### Features

* **monitoring:** adopt 6-digit VMID + DHCP/DNS-first addressing ([#409](https://github.com/dryvist/terraform-proxmox/issues/409)) ([c36ef1e](https://github.com/dryvist/terraform-proxmox/commit/c36ef1e52a2f65f72208efac4990779836c42c1c))

## [1.29.0](https://github.com/dryvist/terraform-proxmox/compare/v1.28.0...v1.29.0) (2026-06-09)


### Features

* **inventory:** publish ansible_inventory to S3 (native aws_s3_object) ([#404](https://github.com/dryvist/terraform-proxmox/issues/404)) ([cef048c](https://github.com/dryvist/terraform-proxmox/commit/cef048cc3b1e84a1f2cf7918cf8f21bfb0da3d58))

## [1.28.0](https://github.com/dryvist/terraform-proxmox/compare/v1.27.0...v1.28.0) (2026-06-09)


### Features

* **monitoring:** harden network-quality stack to Prometheus-native ([#403](https://github.com/dryvist/terraform-proxmox/issues/403)) ([a98962f](https://github.com/dryvist/terraform-proxmox/commit/a98962fa6b4f4501f2aff6d0e76dfb083cdd04ab))

## [1.27.0](https://github.com/dryvist/terraform-proxmox/compare/v1.26.0...v1.27.0) (2026-06-09)


### Features

* **monitoring:** add per-WAN network-diagnosis probers and netmon Splunk index ([#401](https://github.com/dryvist/terraform-proxmox/issues/401)) ([6160211](https://github.com/dryvist/terraform-proxmox/commit/6160211ede91ae04778caea6e72ccf5d74b10289))

## [1.26.0](https://github.com/dryvist/terraform-proxmox/compare/v1.25.1...v1.26.0) (2026-06-09)


### Features

* **ingress:** add Proxmox cluster UI apex route (subdomain apex) ([#400](https://github.com/dryvist/terraform-proxmox/issues/400)) ([147be78](https://github.com/dryvist/terraform-proxmox/commit/147be78016f36d6dba5ded079edf45e8dbaddedd))

## [1.25.1](https://github.com/dryvist/terraform-proxmox/compare/v1.25.0...v1.25.1) (2026-06-07)


### Bug Fixes

* **monitoring:** correct SmokePing vm_id from placeholder 150 to 196 ([#396](https://github.com/dryvist/terraform-proxmox/issues/396)) ([8b52848](https://github.com/dryvist/terraform-proxmox/commit/8b528488215bbb9f3008c615a2e0dc176cd0e41d))

## [1.25.0](https://github.com/dryvist/terraform-proxmox/compare/v1.24.2...v1.25.0) (2026-06-07)


### Features

* **monitoring:** add SmokePing + speedtest network-quality LXC ([#394](https://github.com/dryvist/terraform-proxmox/issues/394)) ([713c35a](https://github.com/dryvist/terraform-proxmox/commit/713c35abf57e4742299314a0f9aa0c7c6ebe5ae7))

## [1.24.2](https://github.com/dryvist/terraform-proxmox/compare/v1.24.1...v1.24.2) (2026-06-07)


### Bug Fixes

* **storage:** replace deprecated proxmox_virtual_environment_datastores with proxmox_datastores ([#392](https://github.com/dryvist/terraform-proxmox/issues/392)) ([9aee7bf](https://github.com/dryvist/terraform-proxmox/commit/9aee7bf655b89c099df5d2be613f3e5daf45132d))

## [1.24.1](https://github.com/dryvist/terraform-proxmox/compare/v1.24.0...v1.24.1) (2026-06-06)


### Bug Fixes

* **splunk-vm:** ignore disk drift to unblock apply on live bootdisk ([#390](https://github.com/dryvist/terraform-proxmox/issues/390)) ([a2a5cf3](https://github.com/dryvist/terraform-proxmox/commit/a2a5cf3752eb20debabad76130fad46d1c63664b))

## [1.24.0](https://github.com/dryvist/terraform-proxmox/compare/v1.23.0...v1.24.0) (2026-06-05)


### Features

* **ingress:** expose Ollama API via Traefik ([#387](https://github.com/dryvist/terraform-proxmox/issues/387)) ([f489003](https://github.com/dryvist/terraform-proxmox/commit/f489003e2767a348f7b8bdd9668ab5d15282e5a9))

## [1.23.0](https://github.com/dryvist/terraform-proxmox/compare/v1.22.3...v1.23.0) (2026-06-05)


### Features

* **secrets:** scaffold OpenBao secrets manager IaC (Raft node 1) ([2d27e0e](https://github.com/dryvist/terraform-proxmox/commit/2d27e0ee5eddc73da53f22ee0c870642844e6701))

## [1.22.3](https://github.com/dryvist/terraform-proxmox/compare/v1.22.2...v1.22.3) (2026-06-04)


### Bug Fixes

* **security:** constrain PBS ISO Renovate version regex ([#383](https://github.com/dryvist/terraform-proxmox/issues/383)) ([39aa2e0](https://github.com/dryvist/terraform-proxmox/commit/39aa2e0f2c1e5f946bc37b42594080d9cffafe84))

## [1.22.2](https://github.com/dryvist/terraform-proxmox/compare/v1.22.1...v1.22.2) (2026-06-04)


### Bug Fixes

* **storage:** bump PBS ISO to 4.2-1, track via Renovate ([#381](https://github.com/dryvist/terraform-proxmox/issues/381)) ([e0c17bc](https://github.com/dryvist/terraform-proxmox/commit/e0c17bc4c5a73383f9b0d90f95dede4a7add17f5))

## [1.22.1](https://github.com/dryvist/terraform-proxmox/compare/v1.22.0...v1.22.1) (2026-06-04)


### Bug Fixes

* **dev:** point nix-devenv flake ref at dryvist owner ([#379](https://github.com/dryvist/terraform-proxmox/issues/379)) ([f8a17b3](https://github.com/dryvist/terraform-proxmox/commit/f8a17b30fba87b1bb9cd39400d7f3cf30bc1b5f8))

## [1.22.0](https://github.com/dryvist/terraform-proxmox/compare/v1.21.0...v1.22.0) (2026-06-04)


### Features

* **backup:** PBS appliance VM (ISO) declaration + ISO var ([#377](https://github.com/dryvist/terraform-proxmox/issues/377)) ([b1f753e](https://github.com/dryvist/terraform-proxmox/commit/b1f753e951b1d2031ab9fb4080264258264b33f5))

## [1.21.0](https://github.com/dryvist/terraform-proxmox/compare/v1.20.0...v1.21.0) (2026-06-04)


### Features

* **storage:** per-dataset ZFS properties in node_storage ([#374](https://github.com/dryvist/terraform-proxmox/issues/374)) ([1bd422b](https://github.com/dryvist/terraform-proxmox/commit/1bd422b98f884335ee34a8b945db91fa004e7a84))

## [1.20.0](https://github.com/dryvist/terraform-proxmox/compare/v1.19.0...v1.20.0) (2026-06-04)


### Features

* **splunk:** mark splunk ingress as https backend ([#372](https://github.com/dryvist/terraform-proxmox/issues/372)) ([0e4926f](https://github.com/dryvist/terraform-proxmox/commit/0e4926f93dbe11d59bc69ecebea319fc1a5bc978))

## [1.19.0](https://github.com/dryvist/terraform-proxmox/compare/v1.18.1...v1.19.0) (2026-06-04)


### Features

* **splunk:** tag splunk NIC onto siem VLAN + front via Traefik ([#369](https://github.com/dryvist/terraform-proxmox/issues/369)) ([6c98875](https://github.com/dryvist/terraform-proxmox/commit/6c9887567900b5fcfa6c3dbaa6ec4895baba489b))

## [1.18.1](https://github.com/dryvist/terraform-proxmox/compare/v1.18.0...v1.18.1) (2026-06-04)


### Bug Fixes

* **vm:** ignore cloud-init ip_config drift to avoid rebuilding the non-removable cloud-init drive ([#366](https://github.com/dryvist/terraform-proxmox/issues/366)) ([920f2a8](https://github.com/dryvist/terraform-proxmox/commit/920f2a8c63a1f18214b0e0bc20eca808c438d281))

## [1.18.0](https://github.com/dryvist/terraform-proxmox/compare/v1.17.0...v1.18.0) (2026-06-04)


### Features

* **ingress:** expose Open WebUI (llm) via Traefik + add LLM service ports ([#362](https://github.com/dryvist/terraform-proxmox/issues/362)) ([2607ca3](https://github.com/dryvist/terraform-proxmox/commit/2607ca340bddbde4c358796f897c17bf04c553ca))

## [1.17.0](https://github.com/dryvist/terraform-proxmox/compare/v1.16.0...v1.17.0) (2026-06-03)


### Features

* **network:** untagged-native NIC support + static IP override ([fa50592](https://github.com/dryvist/terraform-proxmox/commit/fa5059252a133b2f798bc986a0528d8954fac36c))

## [1.16.0](https://github.com/dryvist/terraform-proxmox/compare/v1.15.0...v1.16.0) (2026-06-03)


### Features

* **network:** rename lan_mgmt→mgmt; place Traefik ingress on mgmt VLAN ([#358](https://github.com/dryvist/terraform-proxmox/issues/358)) ([428d3da](https://github.com/dryvist/terraform-proxmox/commit/428d3da174a147cea7ae95e20e230a2ac74ca736))

## [1.15.0](https://github.com/dryvist/terraform-proxmox/compare/v1.14.0...v1.15.0) (2026-06-03)


### Features

* **inventory:** validate ansible_inventory against the schema before sync ([#356](https://github.com/dryvist/terraform-proxmox/issues/356)) ([402c5c9](https://github.com/dryvist/terraform-proxmox/commit/402c5c903f4841a980bc52161e423c9cbc45e027))

## [1.14.0](https://github.com/dryvist/terraform-proxmox/compare/v1.13.0...v1.14.0) (2026-06-03)


### Features

* **ingress:** single inventory-derived ingress route table (DRY) ([#352](https://github.com/dryvist/terraform-proxmox/issues/352)) ([c4bd8f8](https://github.com/dryvist/terraform-proxmox/commit/c4bd8f83d1316aff20caf712e2f14a418b4e4e74))
* **media:** declare Traefik TLS ingress LXC (215) on media VLAN ([#351](https://github.com/dryvist/terraform-proxmox/issues/351)) ([c2b9913](https://github.com/dryvist/terraform-proxmox/commit/c2b9913c0bab63914d91435f7121e3c347fabd17))


### Bug Fixes

* **terragrunt:** resolve inventory sync to public worktree layout ([#349](https://github.com/dryvist/terraform-proxmox/issues/349)) ([a84ae73](https://github.com/dryvist/terraform-proxmox/commit/a84ae73955db914db4d9f5bd5816536b5baa2abf))

## [1.13.0](https://github.com/dryvist/terraform-proxmox/compare/v1.12.0...v1.13.0) (2026-06-02)


### Features

* **ci:** multi-layer secret scanning (gitleaks + private denylist) ([#339](https://github.com/dryvist/terraform-proxmox/issues/339)) ([1cb3e35](https://github.com/dryvist/terraform-proxmox/commit/1cb3e351f4c6b460d82d0eb3e3b66dca23c56b78))
* **sops:** add plex_claim_token to terraform.sops.json ([#347](https://github.com/dryvist/terraform-proxmox/issues/347)) ([63a901f](https://github.com/dryvist/terraform-proxmox/commit/63a901feae00a543b33249f9f704c663b2be2a29))

## [1.12.0](https://github.com/dryvist/terraform-proxmox/compare/v1.11.0...v1.12.0) (2026-06-01)


### Features

* **idrac:** manage idrac-kvm (251) as Docker-in-LXC on ports 5410/5710 ([#324](https://github.com/dryvist/terraform-proxmox/issues/324)) ([7d9d19e](https://github.com/dryvist/terraform-proxmox/commit/7d9d19ec3e3fad43a9b6ca94fa6911340cc7c133))
* **media:** add Jellyseerr request UI (LXC 214) on media_svc ([#336](https://github.com/dryvist/terraform-proxmox/issues/336)) ([3bd4d5f](https://github.com/dryvist/terraform-proxmox/commit/3bd4d5f2333d1391e12343c8edd785d1b17bebe9))
* **media:** redirect stack to proxmox-1 + declare rpool node_storage ([e39a02c](https://github.com/dryvist/terraform-proxmox/commit/e39a02c712302108632c1c696cd83ce4f854f163))
* **media:** VPN-locked media stack LXCs on proxmox-2 (download-vpn/sonarr/radarr/plex) ([#327](https://github.com/dryvist/terraform-proxmox/issues/327)) ([4673dc8](https://github.com/dryvist/terraform-proxmox/commit/4673dc8f34cd94f818ae5445a1824e43ee8c5340))
* **multi-node:** node placement, proxmox-2/proxmox-3 storage, safety gates ([#325](https://github.com/dryvist/terraform-proxmox/issues/325)) ([6b3277f](https://github.com/dryvist/terraform-proxmox/commit/6b3277f4e8764f27f0cdc3bb1f62e1a0c1cb3c4b))
* **network:** per-VLAN CIDR model replacing flat network_prefix ([#331](https://github.com/dryvist/terraform-proxmox/issues/331)) ([72b292d](https://github.com/dryvist/terraform-proxmox/commit/72b292d1b11181ef3b2c68c77b9e935d4b7ff99a))


### Bug Fixes

* **ci:** repoint release-please caller to org-native reusable workflow ([#342](https://github.com/dryvist/terraform-proxmox/issues/342)) ([31b8e07](https://github.com/dryvist/terraform-proxmox/commit/31b8e07dddecee33ce123b32d3437bbfe929b1b3))
* **ci:** retarget reusable-workflow uses: refs to current org homes ([#326](https://github.com/dryvist/terraform-proxmox/issues/326)) ([c7b2def](https://github.com/dryvist/terraform-proxmox/commit/c7b2def173e2d7ce16db4cf1d2a70e547d573f21))
* **media:** align node_name with live PVE member name proxmox-1 ([6420bdd](https://github.com/dryvist/terraform-proxmox/commit/6420bdd0839d5a187ef89cb90794201682be5ca5))

## [1.11.0](https://github.com/JacobPEvans/terraform-proxmox/compare/v1.10.1...v1.11.0) (2026-05-25)


### Features

* **acme:** SAN list + per-LXC/VM cert delivery via null_resource ([#320](https://github.com/JacobPEvans/terraform-proxmox/issues/320)) ([591071a](https://github.com/JacobPEvans/terraform-proxmox/commit/591071a6fa2a7e841610b8107a1dd0d6e3dfe698))

## [1.10.1](https://github.com/JacobPEvans/terraform-proxmox/compare/v1.10.0...v1.10.1) (2026-05-25)


### Bug Fixes

* **deployment:** drop keyctl/fuse from infisical+openproject features ([#318](https://github.com/JacobPEvans/terraform-proxmox/issues/318)) ([fdc4d36](https://github.com/JacobPEvans/terraform-proxmox/commit/fdc4d3613a2a73a6498e7fac0545eff4afbc7c94))

## [1.10.0](https://github.com/JacobPEvans/terraform-proxmox/compare/v1.9.1...v1.10.0) (2026-05-24)


### Features

* provision Infisical LXC at vm_id 108 with firewall + DRY constants ([#315](https://github.com/JacobPEvans/terraform-proxmox/issues/315)) ([17ef7ea](https://github.com/JacobPEvans/terraform-proxmox/commit/17ef7ea761ed42766d9fba2d3e1071c025e9aee5))

## [1.9.1](https://github.com/JacobPEvans/terraform-proxmox/compare/v1.9.0...v1.9.1) (2026-05-24)


### Bug Fixes

* initialize OpenTofu in Copilot setup workflow ([#301](https://github.com/JacobPEvans/terraform-proxmox/issues/301)) ([84fa2f1](https://github.com/JacobPEvans/terraform-proxmox/commit/84fa2f10d90f0ca41368271dea7102b58bccc228))

## [1.9.0](https://github.com/JacobPEvans/terraform-proxmox/compare/v1.8.0...v1.9.0) (2026-05-20)


### Features

* **poweredge:** declarative inventory module for cluster join ([#296](https://github.com/JacobPEvans/terraform-proxmox/issues/296)) ([40fabb3](https://github.com/JacobPEvans/terraform-proxmox/commit/40fabb3b594a2bc6428ef38119b0e445bfed150e))

## [1.8.0](https://github.com/JacobPEvans/terraform-proxmox/compare/v1.7.0...v1.8.0) (2026-05-16)


### Features

* **firewall:** add idrac-kvm VM 251 with tag-driven internal firewall ([#294](https://github.com/JacobPEvans/terraform-proxmox/issues/294)) ([a67c2fa](https://github.com/JacobPEvans/terraform-proxmox/commit/a67c2fab125a2074d371797678c6c88205d97264))
* **firewall:** allow UDP/123 from VM subnets to Proxmox hosts ([#290](https://github.com/JacobPEvans/terraform-proxmox/issues/290)) ([c55ed2f](https://github.com/JacobPEvans/terraform-proxmox/commit/c55ed2f2f5814b8c06ef3b6602a4b3fb9d6db535)), closes [#285](https://github.com/JacobPEvans/terraform-proxmox/issues/285)

## [1.7.0](https://github.com/JacobPEvans/terraform-proxmox/compare/v1.6.5...v1.7.0) (2026-05-14)


### Features

* **containers:** add OpenProject Community Edition LXC ([#284](https://github.com/JacobPEvans/terraform-proxmox/issues/284)) ([4d7cead](https://github.com/JacobPEvans/terraform-proxmox/commit/4d7ceadfdd7e49704eaedb9868516f23dbac77b1))

## [1.6.5](https://github.com/JacobPEvans/terraform-proxmox/compare/v1.6.4...v1.6.5) (2026-05-07)


### Bug Fixes

* **acme:** complete proxmox_acme_* rename with state migration ([#270](https://github.com/JacobPEvans/terraform-proxmox/issues/270)) ([5afe3f1](https://github.com/JacobPEvans/terraform-proxmox/commit/5afe3f1aeb614603914fa005a65c544bfcc38b50))
* **tests:** add missing validation tests for 17 variable blocks ([#272](https://github.com/JacobPEvans/terraform-proxmox/issues/272)) ([1e999ed](https://github.com/JacobPEvans/terraform-proxmox/commit/1e999ed218d1eef9c1f5af6483a40e51800c275e))

## [1.6.4](https://github.com/JacobPEvans/terraform-proxmox/compare/v1.6.3...v1.6.4) (2026-05-06)


### Bug Fixes

* re-enable checkov security scanning, bump rev to 3.2.526 ([#126](https://github.com/JacobPEvans/terraform-proxmox/issues/126)) [issue-solver-2026-05-06] ([736909e](https://github.com/JacobPEvans/terraform-proxmox/commit/736909e171da3fe884643b51787a306b6c0023af))

## [1.6.3](https://github.com/JacobPEvans/terraform-proxmox/compare/v1.6.2...v1.6.3) (2026-05-06)


### Bug Fixes

* **ci:** remove deprecated app-id secret passthrough ([a9b2cbd](https://github.com/JacobPEvans/terraform-proxmox/commit/a9b2cbd78b27d200b7b57916e828e1ca7057cd9a))

## [1.6.2](https://github.com/JacobPEvans/terraform-proxmox/compare/v1.6.1...v1.6.2) (2026-04-21)


### Bug Fixes

* add bot PR CI retrigger workflow ([#261](https://github.com/JacobPEvans/terraform-proxmox/issues/261)) ([91a8814](https://github.com/JacobPEvans/terraform-proxmox/commit/91a88141e1932cb42499a59c60513e800433e0f4))

## [1.6.1](https://github.com/JacobPEvans/terraform-proxmox/compare/v1.6.0...v1.6.1) (2026-04-18)


### Bug Fixes

* assume credentials in environment for pre-push hooks ([#258](https://github.com/JacobPEvans/terraform-proxmox/issues/258)) ([fd1eca1](https://github.com/JacobPEvans/terraform-proxmox/commit/fd1eca10447c6e031d0d48d528b70e281d69b641))

## [1.6.0](https://github.com/JacobPEvans/terraform-proxmox/compare/v1.5.3...v1.6.0) (2026-04-18)


### Features

* declare Samba NAS inventory contract ([#254](https://github.com/JacobPEvans/terraform-proxmox/issues/254)) ([6ac67b3](https://github.com/JacobPEvans/terraform-proxmox/commit/6ac67b3ba5b047f050b96a7e2b6c0e1455e95b44))

## [1.5.3](https://github.com/JacobPEvans/terraform-proxmox/compare/v1.5.2...v1.5.3) (2026-04-13)


### Bug Fixes

* recompile gh-aw workflows with v0.68.1 ([d858ec3](https://github.com/JacobPEvans/terraform-proxmox/commit/d858ec311d9659acfd6df7494b643354ad281edb))

## [1.5.2](https://github.com/JacobPEvans/terraform-proxmox/compare/v1.5.1...v1.5.2) (2026-04-12)


### Bug Fixes

* correct Cribl Stream API port to 9000 ([#228](https://github.com/JacobPEvans/terraform-proxmox/issues/228)) ([a42f6bb](https://github.com/JacobPEvans/terraform-proxmox/commit/a42f6bbf823a7b082ab9daf6efec2adc60b04bc1))

## [1.5.1](https://github.com/JacobPEvans/terraform-proxmox/compare/v1.5.0...v1.5.1) (2026-04-12)


### Bug Fixes

* correct Cribl Edge API port to 9420 and support assumed-role credentials in hooks ([#223](https://github.com/JacobPEvans/terraform-proxmox/issues/223)) ([9e2ff12](https://github.com/JacobPEvans/terraform-proxmox/commit/9e2ff12c2745d2f4c6ec6804171dd219c402026f))

## [1.5.0](https://github.com/JacobPEvans/terraform-proxmox/compare/v1.4.0...v1.5.0) (2026-04-08)


### Features

* add AI merge gate ([#215](https://github.com/JacobPEvans/terraform-proxmox/issues/215)) ([c45e616](https://github.com/JacobPEvans/terraform-proxmox/commit/c45e61639230a0c315e59cdf1975d4f8ca73b160))

## [1.4.0](https://github.com/JacobPEvans/terraform-proxmox/compare/v1.3.2...v1.4.0) (2026-04-07)


### Features

* add MinIO LXC container for artifact storage ([#216](https://github.com/JacobPEvans/terraform-proxmox/issues/216)) ([2b16d08](https://github.com/JacobPEvans/terraform-proxmox/commit/2b16d0849b1314aae096d1a2a0da56a77b15557d))

## [1.3.2](https://github.com/JacobPEvans/terraform-proxmox/compare/v1.3.1...v1.3.2) (2026-04-04)


### Bug Fixes

* remove claude-review workflow — replaced by Gemini + Copilot ([#212](https://github.com/JacobPEvans/terraform-proxmox/issues/212)) ([928b6f6](https://github.com/JacobPEvans/terraform-proxmox/commit/928b6f6c90426b108074cf23a5c24c22d72902ce))

## [1.3.1](https://github.com/JacobPEvans/terraform-proxmox/compare/v1.3.0...v1.3.1) (2026-04-02)


### Bug Fixes

* use nix-devenv terraform shell instead of local flake.nix ([#210](https://github.com/JacobPEvans/terraform-proxmox/issues/210)) ([e1b7a61](https://github.com/JacobPEvans/terraform-proxmox/commit/e1b7a61a82cb7419cdd3983629381a5f611fa44f))

## [1.3.0](https://github.com/JacobPEvans/terraform-proxmox/compare/v1.2.1...v1.3.0) (2026-03-25)


### Features

* auto-sync inventory to downstream repos after apply ([#207](https://github.com/JacobPEvans/terraform-proxmox/issues/207)) ([2fc6fb4](https://github.com/JacobPEvans/terraform-proxmox/commit/2fc6fb47d3b5c65fece2c280f675464dec73680e))

## [1.2.1](https://github.com/JacobPEvans/terraform-proxmox/compare/v1.2.0...v1.2.1) (2026-03-25)


### Bug Fixes

* sync terragrunt provider version with main.tf ([#206](https://github.com/JacobPEvans/terraform-proxmox/issues/206)) ([e9a6ef7](https://github.com/JacobPEvans/terraform-proxmox/commit/e9a6ef7e9d7d613211d773925c00250faad47559))

## [1.2.0](https://github.com/JacobPEvans/terraform-proxmox/compare/v1.1.0...v1.2.0) (2026-03-22)


### Features

* add FQDN auto-config and pipeline container definitions ([#185](https://github.com/JacobPEvans/terraform-proxmox/issues/185)) ([7f2a6e4](https://github.com/JacobPEvans/terraform-proxmox/commit/7f2a6e42b19783cb64e5d5ab1657f684b3e7b034))
* add host-level NAS storage config for ansible-proxmox consumption ([#184](https://github.com/JacobPEvans/terraform-proxmox/issues/184)) ([71fa736](https://github.com/JacobPEvans/terraform-proxmox/commit/71fa736e9d76baf1719c12313b86e9810f2a7bde))
* add LlamaIndex container and fix Qdrant swap ([#194](https://github.com/JacobPEvans/terraform-proxmox/issues/194)) ([54f42d3](https://github.com/JacobPEvans/terraform-proxmox/commit/54f42d3d328170b3dad47632f0c73c0dada97171))
* complete deployment.json migration, delete terraform.tfvars ([#186](https://github.com/JacobPEvans/terraform-proxmox/issues/186)) ([30cef3c](https://github.com/JacobPEvans/terraform-proxmox/commit/30cef3c95ae01dd7dbced434dc6021f11c6e3116))


### Bug Fixes

* add .file-size.yml with extended limit for TROUBLESHOOTING ([#199](https://github.com/JacobPEvans/terraform-proxmox/issues/199)) ([5da46ee](https://github.com/JacobPEvans/terraform-proxmox/commit/5da46ee867f301244e20140bf5dfee1fdf62f1ae))
* add release-please config for manifest mode ([f17447f](https://github.com/JacobPEvans/terraform-proxmox/commit/f17447f8f0550451b6571cc352fcf7238232f0dd))
* add syslog and netflow firewall rules to Cribl Stream containers ([#189](https://github.com/JacobPEvans/terraform-proxmox/issues/189)) ([51737aa](https://github.com/JacobPEvans/terraform-proxmox/commit/51737aa0b845d321a3a0af3c2073a2328f98071d))
* **ci:** add pull-requests:write for release-please auto-approve ([8dfe391](https://github.com/JacobPEvans/terraform-proxmox/commit/8dfe391755961c81aa0ed6a2363a4bdf188df6bb))
* **ci:** implement Merge Gatekeeper pattern with ci-gate.yml ([#187](https://github.com/JacobPEvans/terraform-proxmox/issues/187)) ([dc3126f](https://github.com/JacobPEvans/terraform-proxmox/commit/dc3126fca6e86f7698b489d3080d18eb942cf4eb))
* split oversized files and resolve lint errors blocking CI ([#203](https://github.com/JacobPEvans/terraform-proxmox/issues/203)) ([36b77df](https://github.com/JacobPEvans/terraform-proxmox/commit/36b77df4fae09fecd65889ddfaf68b01f53acff0))
* sync release-please config, permissions, VERSION, and unpin workflow ([c8f7b1a](https://github.com/JacobPEvans/terraform-proxmox/commit/c8f7b1a0a7548ebfaf0498adc2428602279fe27a))

## [1.1.0](https://github.com/JacobPEvans/terraform-proxmox/compare/v1.0.0...v1.1.0) (2026-03-11)


### Features

* add ansible_inventory output for dynamic Ansible integration ([#85](https://github.com/JacobPEvans/terraform-proxmox/issues/85)) ([8835db4](https://github.com/JacobPEvans/terraform-proxmox/commit/8835db429834cec83894eac55655720111744dca))
* add apt-cacher-ng LXC container (VMID 106) ([#179](https://github.com/JacobPEvans/terraform-proxmox/issues/179)) ([ad3efcb](https://github.com/JacobPEvans/terraform-proxmox/commit/ad3efcba1b574fea9cf31969cc46b88620a98d53))
* add CI auto-fix workflow and replace Claude Code placeholder ([#104](https://github.com/JacobPEvans/terraform-proxmox/issues/104)) ([79c2b93](https://github.com/JacobPEvans/terraform-proxmox/commit/79c2b9386c4079e7a8d683ad6b605eeaf9fe3365))
* add daily repo health audit agentic workflow ([#181](https://github.com/JacobPEvans/terraform-proxmox/issues/181)) ([4a16c51](https://github.com/JacobPEvans/terraform-proxmox/commit/4a16c5126e721cc09a4c0ec9384eddd844e71d35))
* add dynamic startup order to VM and container modules ([#78](https://github.com/JacobPEvans/terraform-proxmox/issues/78)) ([4adf4fb](https://github.com/JacobPEvans/terraform-proxmox/commit/4adf4fb834fa9ad7c458a4f70f3183ca20a834cb))
* add final PR review workflow ([#107](https://github.com/JacobPEvans/terraform-proxmox/issues/107)) ([e0cdb86](https://github.com/JacobPEvans/terraform-proxmox/commit/e0cdb8618275c6315f8a8acf09c01618c152088b))
* add HAProxy container, Cribl storage, and fix Splunk disk layout ([#82](https://github.com/JacobPEvans/terraform-proxmox/issues/82)) ([35abfb9](https://github.com/JacobPEvans/terraform-proxmox/commit/35abfb9164bbb44454854df9e20bb42e2ae1e832))
* add mailpit and ntfy LXC containers for notification services ([#132](https://github.com/JacobPEvans/terraform-proxmox/issues/132)) ([0545d8b](https://github.com/JacobPEvans/terraform-proxmox/commit/0545d8bb1ba52e9c0e2eb1a615f49c6ec116507a))
* add native SOPS/age integration via sops_decrypt_file() ([#113](https://github.com/JacobPEvans/terraform-proxmox/issues/113)) ([faf7bb2](https://github.com/JacobPEvans/terraform-proxmox/commit/faf7bb2f7da3377bff01dce23b9e6b9084169fa5))
* add netflow_ports to pipeline_constants and update docs ([#111](https://github.com/JacobPEvans/terraform-proxmox/issues/111)) ([267c4c1](https://github.com/JacobPEvans/terraform-proxmox/commit/267c4c12432f5ae895e40eb7dc581879cb4f4b49))
* add per-repo devShell with Terraform/Terragrunt tools ([#154](https://github.com/JacobPEvans/terraform-proxmox/issues/154)) ([3b05327](https://github.com/JacobPEvans/terraform-proxmox/commit/3b053271ae614d9d4c38187846a4eacd375b78bd))
* add Pi-Hole DNS container to infrastructure tier (ID 104) ([#80](https://github.com/JacobPEvans/terraform-proxmox/issues/80)) ([e735315](https://github.com/JacobPEvans/terraform-proxmox/commit/e7353153ae7b157c699a64678fa3aebb87555414))
* add Qdrant vector database container with firewall rules ([#177](https://github.com/JacobPEvans/terraform-proxmox/issues/177)) ([7a23464](https://github.com/JacobPEvans/terraform-proxmox/commit/7a23464c8610e7c0669ea8d3e987e57c9774be80))
* add SOPS/age secrets management integration ([e7518b7](https://github.com/JacobPEvans/terraform-proxmox/commit/e7518b7e244007ac3f813afebb0a4e7849c18581))
* adopt conventional branch standard (feature/, bugfix/) ([#168](https://github.com/JacobPEvans/terraform-proxmox/issues/168)) ([cb4cef8](https://github.com/JacobPEvans/terraform-proxmox/commit/cb4cef8eda1d531b89648ef33fc277e14a4b7ce5))
* auto-enable squash merge on all PRs when opened ([#144](https://github.com/JacobPEvans/terraform-proxmox/issues/144)) ([80d0ce8](https://github.com/JacobPEvans/terraform-proxmox/commit/80d0ce884e2a0d5bda0dd733cc27e5a9b793c059))
* **ci:** unified issue dispatch pattern with AI-created issue support ([#131](https://github.com/JacobPEvans/terraform-proxmox/issues/131)) ([7484143](https://github.com/JacobPEvans/terraform-proxmox/commit/74841430c3f0888ecfc698acc9754fe613b6e089))
* consolidate Splunk Docker deployment to ansible-splunk ([#90](https://github.com/JacobPEvans/terraform-proxmox/issues/90)) ([b26a848](https://github.com/JacobPEvans/terraform-proxmox/commit/b26a84878091ef00d9bba25b4e299e365bd2cb4f))
* **copilot:** add Copilot coding agent support + CI fail issue workflow ([#143](https://github.com/JacobPEvans/terraform-proxmox/issues/143)) ([64d6f43](https://github.com/JacobPEvans/terraform-proxmox/commit/64d6f4359f2ae6cad54d98225daf53dfcac88b01))
* create ansible inventory export script ([#88](https://github.com/JacobPEvans/terraform-proxmox/issues/88)) ([55a878d](https://github.com/JacobPEvans/terraform-proxmox/commit/55a878d03b138e4f25a9864da679dbcf1326b51d))
* disable automatic triggers on Claude-executing workflows ([41177a5](https://github.com/JacobPEvans/terraform-proxmox/commit/41177a5ae5e34dc6b5e0b86196180c346fb5be09))
* **firewall:** add netflow security group for UDP 2055 ([#93](https://github.com/JacobPEvans/terraform-proxmox/issues/93)) ([f742ab9](https://github.com/JacobPEvans/terraform-proxmox/commit/f742ab93186e71688ea4797232204919ee67dd6a))
* fuse LXC feature, dynamic container module, SOPS ssh username ([#134](https://github.com/JacobPEvans/terraform-proxmox/issues/134)) ([b66a4bc](https://github.com/JacobPEvans/terraform-proxmox/commit/b66a4bc427903268bc46027c9b3e3fbab27ee05b))
* **gh-aw:** add autonomous agentic workflows (Copilot engine) ([#151](https://github.com/JacobPEvans/terraform-proxmox/issues/151)) ([156120c](https://github.com/JacobPEvans/terraform-proxmox/commit/156120ca9add9b3e17d9c8fcc1de57b2d3d93a68))
* implement Docker-based Splunk VM with UniFi syslog ingestion ([#83](https://github.com/JacobPEvans/terraform-proxmox/issues/83)) ([f1fb448](https://github.com/JacobPEvans/terraform-proxmox/commit/f1fb448b702bdb2c858a22ca8a16603a21940bd0))
* **packer:** add systemd restart policy for Splunk service ([#79](https://github.com/JacobPEvans/terraform-proxmox/issues/79)) ([c84bebe](https://github.com/JacobPEvans/terraform-proxmox/commit/c84bebee7928c9393541d267b6cb4e24f91b1c9d))
* **pipeline:** add static IPs, docker_vms output, testing, and validation ([#99](https://github.com/JacobPEvans/terraform-proxmox/issues/99)) ([28a08c3](https://github.com/JacobPEvans/terraform-proxmox/commit/28a08c3ec33efc77b8e1adc0e25e9622e798f6eb))
* **renovate:** extend shared preset for org-wide auto-merge rules ([#148](https://github.com/JacobPEvans/terraform-proxmox/issues/148)) ([8a93126](https://github.com/JacobPEvans/terraform-proxmox/commit/8a9312614cdf6b7840f78130a217f79bf76aa6ad))
* split config into deployment.json (plaintext) + tiny SOPS + derived networks ([#129](https://github.com/JacobPEvans/terraform-proxmox/issues/129)) ([21f40dd](https://github.com/JacobPEvans/terraform-proxmox/commit/21f40dd805328a459afe186c736c74eaa30777f3))
* switch to ai-workflows reusable workflows ([#108](https://github.com/JacobPEvans/terraform-proxmox/issues/108)) ([c189b53](https://github.com/JacobPEvans/terraform-proxmox/commit/c189b53324501da42fac7134ec258262f8344db2))
* **terraform:** add vga_type support and env-specific tfvars loading ([#75](https://github.com/JacobPEvans/terraform-proxmox/issues/75)) ([1dd4710](https://github.com/JacobPEvans/terraform-proxmox/commit/1dd4710aa1673bfde98fa369a82d78f328dd2bea))


### Bug Fixes

* add splunk VM lifecycle protection and remove dead variables ([#115](https://github.com/JacobPEvans/terraform-proxmox/issues/115)) ([134e3eb](https://github.com/JacobPEvans/terraform-proxmox/commit/134e3ebf699e367bcf3835667c5232f75d82dc62))
* address devShell review feedback ([#155](https://github.com/JacobPEvans/terraform-proxmox/issues/155)) ([40b3947](https://github.com/JacobPEvans/terraform-proxmox/commit/40b3947afd806ed953f68657b4a4b86674b9fb20))
* address devShell review feedback ([#156](https://github.com/JacobPEvans/terraform-proxmox/issues/156)) ([0c6ca50](https://github.com/JacobPEvans/terraform-proxmox/commit/0c6ca506525d21a43a7e1946a7af5badf7ffc3b0))
* bump ai-workflows callers to v0.2.9 and add OIDC permissions ([#120](https://github.com/JacobPEvans/terraform-proxmox/issues/120)) ([0bb4a6c](https://github.com/JacobPEvans/terraform-proxmox/commit/0bb4a6c116b1dd41c201537ccc07f5f5e41515fb))
* bump all ai-workflows callers to v0.2.6 and add id-token:write ([#119](https://github.com/JacobPEvans/terraform-proxmox/issues/119)) ([3e6b4ef](https://github.com/JacobPEvans/terraform-proxmox/commit/3e6b4ef772a295315e727b419f5082d34ab393f1))
* bump all callers to ai-workflows v0.2.3 with explicit permissions ([#118](https://github.com/JacobPEvans/terraform-proxmox/issues/118)) ([781e621](https://github.com/JacobPEvans/terraform-proxmox/commit/781e6212ff8b9a3a6a7bdff5b5813320f973363f))
* **ci:** add dispatch pattern for post-merge and bot guard for triage ([#127](https://github.com/JacobPEvans/terraform-proxmox/issues/127)) ([64f2bcd](https://github.com/JacobPEvans/terraform-proxmox/commit/64f2bcda03cecfa6a470ef1314528e7b9ea85070))
* correct CIDR notation from /32 to /24 for standard LAN hosts ([32a5fc7](https://github.com/JacobPEvans/terraform-proxmox/commit/32a5fc7b910b5a6229b9c5200535be608edc9dc2))
* **docs:** replace leaked 10.0.1.x IPs with 192.168.1.x placeholders ([f45d476](https://github.com/JacobPEvans/terraform-proxmox/commit/f45d47652876434d862ac1f4c1fa39712e60e23b))
* **docs:** use /32 subnet mask and correct RFC reference ([41bfbd1](https://github.com/JacobPEvans/terraform-proxmox/commit/41bfbd1f2014ce30784aa4c6983f6fb05f99c1b6))
* **firewall:** add cluster firewall resource to enable VM-level rules ([#92](https://github.com/JacobPEvans/terraform-proxmox/issues/92)) ([98be51f](https://github.com/JacobPEvans/terraform-proxmox/commit/98be51f980dad1da118fe847358d61203e461ec3))
* **firewall:** add missing pipeline container port rules ([#114](https://github.com/JacobPEvans/terraform-proxmox/issues/114)) ([7918acf](https://github.com/JacobPEvans/terraform-proxmox/commit/7918acf55ff1980b584ee15e091d4bd87ef32c33))
* Packer template ID 9200 for Splunk Docker ([#91](https://github.com/JacobPEvans/terraform-proxmox/issues/91)) ([5f1f7d8](https://github.com/JacobPEvans/terraform-proxmox/commit/5f1f7d85fe78d4540617017fa15756f2a0a64dd3))
* remove .envrc from git tracking ([a714a89](https://github.com/JacobPEvans/terraform-proxmox/commit/a714a891153e6c1a6717d25f5910344ca90dcdec))
* remove blanket auto-merge workflow ([#171](https://github.com/JacobPEvans/terraform-proxmox/issues/171)) ([7920027](https://github.com/JacobPEvans/terraform-proxmox/commit/79200277f3a9d50e4616211dac077a647b26c96f))
* **splunk:** increase resources and fix data disk setup ([#110](https://github.com/JacobPEvans/terraform-proxmox/issues/110)) ([d0cd071](https://github.com/JacobPEvans/terraform-proxmox/commit/d0cd0713cf19d3facd6d4988b299bd7ba2c7ea19))
* use coalesce() for container IP derivation fallback ([#84](https://github.com/JacobPEvans/terraform-proxmox/issues/84)) ([be39d8e](https://github.com/JacobPEvans/terraform-proxmox/commit/be39d8e61aa16b14cc7bc1335f377e0fec2e2b81))
* use SPLUNK_ADMIN_PASSWORD envvar name to match Doppler ([#95](https://github.com/JacobPEvans/terraform-proxmox/issues/95)) ([3531043](https://github.com/JacobPEvans/terraform-proxmox/commit/3531043a8dac0025887b13e1a150ed05828f11a7))
