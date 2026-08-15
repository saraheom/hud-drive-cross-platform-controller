// v55 compatibility shim.
//
// The Persistent Text / Music Probe experiment was removed in v53.
// This file intentionally remains as an inert overwrite target for repositories
// that are updated by copying a newer ZIP over an older Git checkout.
//
// project.yml explicitly excludes this file from the HUDController target, so
// nothing here is compiled into the application.
//
// DO NOT restore HudTextRendererProbe, textNotificationProbe, or
// persistentNavigationTextProbe here.
