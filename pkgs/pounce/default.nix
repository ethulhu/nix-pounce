# SPDX-FileCopyrightText: 2022 Ethel Morgan
#
# SPDX-License-Identifier: MIT

{ curl, fetchgit, lib, libressl, libxcrypt, pkg-config, sqlite, stdenv }:

stdenv.mkDerivation {
  pname = "pounce";
  version = "latest";

  src = fetchgit {
    url = "https://git.causal.agency/pounce";
    hash = "sha256-DW+iXOVCIn+G4IZ5ULwU14WzaBw0V6qmoBidl+bEfpQ=";
    rev = "81608f2dd47a5ea42ac4c5e849fd4fd136facc5b";
  };

  buildInputs = [ curl.dev libressl libxcrypt sqlite ];

  configureFlags = [ "--enable-edit" "--enable-notify" "--enable-palaver" ];

  nativeBuildInputs = [ pkg-config ];

  buildFlags = [ "all" ];

  meta = with lib; {
    homepage = "https://git.causal.agency/pounce/about/";
    description = "IRC pouncer :3";
    license = licenses.gpl3;
  };
}
