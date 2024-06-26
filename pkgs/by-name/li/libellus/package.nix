{
  stdenv,
  lib,
  fetchFromGitHub,
  meson,
  ninja,
  desktop-file-utils,
  glib,
  gjs,
  gtk3,
  wrapGAppsHook
}:

stdenv.mkDerivation rec {
  pname = "libellus";
  version = "1.0.3.1";

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
    wrapGAppsHook
  ];

  buildInputs = [
    gtk3
    glib
    wrapGAppsHook
  ];

  meta = {
    description = "";
    homepage = "";
    license = lib.licenses.gpl3Plus;
    longDescription = '''';
    maintainers = with lib.maintainers; [ wentasah ];
    platforms = lib.platforms.linux;
    mainProgram = "de.hummdudel.Libellus";
  };
}
