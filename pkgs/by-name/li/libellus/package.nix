{
  stdenv,
  lib,
  fetchFromGitHub,
  meson,
  ninja,
  desktop-file-utils,
  glib,
  gjs,
  wrapGAppsHook4,
  gobject-introspection,
  gettext,
  appstream-glib,
  pkg-config,
  cmake,
  gtk4,
}:

stdenv.mkDerivation rec {
  pname = "libellus";
  version = "1.0.3";

  src = fetchFromGitHub {
    owner = "qwertzuiopy";
    repo = "Libellus";
    rev = "v${version}";
    sha256 = "sha256-TjPARU1jrZVOBCqSEUeCZj5KkAnalmoRcf3IbUcqxgI=";
  };

  nativeBuildInputs = [
    meson
    ninja
    gjs
    desktop-file-utils
    glib
    wrapGAppsHook4
    gobject-introspection
    gettext
    appstream-glib
    pkg-config
    cmake
    gtk4
  ];

  buildInputs = [
    glib

  ];

  postInstall = ''
    mv $out/bin/de.hummdudel.Libellus $out/bin/libellus
  '';

  meta = {
    description = "";
    homepage = "";
    license = lib.licenses.gpl3Plus;
    longDescription = '''';
    maintainers = with lib.maintainers; [ nydragon ];
    platforms = lib.platforms.linux;
    mainProgram = "libellus";
  };
}
