# SPDX-FileCopyrightText: 2022 Ethel Morgan
#
# SPDX-License-Identifier: MIT

{ fetchzip, lib, libressl, pkgconfig, sqlite, stdenv }:
stdenv.mkDerivation rec {
  pname = "litterbox";
  version = "1.8";

  src = fetchzip {
    url =
      "https://git.causal.agency/litterbox/snapshot/litterbox-${version}.tar.gz";
    hash = "sha256-KD+Jcwsz7yxpZzF+yj5j4eSsAIFy4icUknAWFJzCVjs=";
  };

  buildInputs = [ libressl sqlite ];

  nativeBuildInputs = [ pkgconfig ];

  buildFlags = [ "all" ];

  meta = with lib; {
    homepage = "https://code.causal.agency/june/litterbox";
    description = "IRC logger";
    license = licenses.gpl3;
  };
}
