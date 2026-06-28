/**
 * Deft — a native UI framework for the D programming language.
 *
 * Deft wraps native platform controls (Win32 today; GTK4 and Cocoa later) and
 * provides a delegate-based event system together with an automatic layout
 * engine. This module is the public entry point: import `deft` to pull in the
 * core types.
 *
 * Public re-exports are added here as each subsystem lands.
 */
module deft;

public import deft.util.strings;
public import deft.events;
public import deft.widget;
public import deft.window;
public import deft.app;
public import deft.layout;
public import deft.controls.control;
public import deft.commandqueue;
public import deft.accessibility;
