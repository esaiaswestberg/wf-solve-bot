#!/bin/bash
adb logcat --pid=$(adb shell pidof tech.low_stack.qy)
