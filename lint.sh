#!/usr/bin/env bash

set -ex

zig fmt .
zig test day01/main.zig
zig test day02/main.zig
zig test day03/main.zig
zig test day04/main.zig
zig test day05/main.zig
zig test day06/main.zig
zig test day07/main.zig
zig test day08/main.zig
zig test day09/main.zig
