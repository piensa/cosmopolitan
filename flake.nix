{
  description = "Cosmopolitan Libc makes C a build-once run-anywhere language";

  inputs.nixpkgs.follows = "nix/nixpkgs";

  outputs = { self, nix, nixpkgs }:

    let
      supportedSystems = [ "x86_64-linux" "i686-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems (system: f system);
      version = "0.1.${nixpkgs.lib.substring 0 8 self.lastModifiedDate}.${self.shortRev or "dirty"}";
    in

    {

      overlay = final: prev: rec {

        cosmopolitan = with final; let nix = final.nix; in stdenv.mkDerivation {
          name = "cosmopolitan-${version}";
          version = "unstable";
          nativeBuildInputs = [ makeWrapper ];

	  preBuild = ''
	    makeFlagsArray=(SHELL=/bin/sh HOSTS=rhel7 "MKDIR=mkdir -p")
	  '';

          NIX_CFLAGS_COMPILE = "-I ${nix.dev}/include/nix -include ${nix.dev}/include/nix/config.h -D_FILE_OFFSET_BITS=64 -DVERSION=\"${version}\"";

          src = self;

	  installPhase = ''
	    runHook preInstall
	    mkdir -p $out/{bin,lib/include}
	    install o/cosmopolitan.h $out/lib/include
	    install o/cosmopolitan.h $out/lib
	    install o/cosmopolitan.a o/libc/crt/crt.o o/ape/ape.{o,lds} $out/lib
	    makeWrapper ${gcc}/bin/gcc $out/bin/cosmoc --add-flags "-O -static -nostdlib -nostdinc -fno-pie -no-pie -mno-red-zone -fuse-ld=bfd -Wl,-T,$out/lib/ape.lds -include $out/lib/include/cosmopolitan.h $out/lib/{crt.o,ape.o,cosmopolitan.a}"
	    runHook postInstall
	  '';

          testPhase = ''
            printf 'main() { printf("hello world\\n"); }\n' >hello.c
            CPPFLAGS=-DSUPPORT_VECTOR=0b1110011 gcc -g -O -static -nostdlib -nostdinc -fno-pie -no-pie -mno-red-zone -o hello.elf hello.c -fuse-ld=bfd -Wl,-T,ape.lds -include cosmopolitan.h crt.o ape.o cosmopolitan.a
            objcopy -S -O binary hello.elf hello
            ./hello
          '';

          outputs = [ "lib" "bin" ];
        };

      };

      defaultPackage = forAllSystems (system: (import nixpkgs {
        inherit system;
        overlays = [ self.overlay nix.overlay ];
      }).cosmopolitan);

      checks = forAllSystems (system: {
        build = self.defaultPackage.${system};

        test =
          with import (nixpkgs + "/nixos/lib/testing-python.nix") {
            inherit system;
          };

          makeTest {
            nodes = {
              client = { ... }: {
                nixpkgs.overlays = [ nix.overlay ];
              };
            };

            testScript =
              ''
                client.succeed("lua --version")
              '';
          };
      });
   };
}
