#!/usr/bin/env bash

set -ex

zig fmt .
zig test day1/main.zig
zig test day2/main.zig
zig test day3/main.zig
zig test day4/main.zig
zig test day5/main.zig
