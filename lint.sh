#!/usr/bin/env bash

set -ex

zig fmt .
zig test day1/main.zig
zig test day2/main.zig
zig test day3/main.zig
zig test day4/main.zig
zig test day5/main.zig
zig test day6/main.zig
zig test day7/main.zig
zig test day8/main.zig
zig test day9/main.zig
