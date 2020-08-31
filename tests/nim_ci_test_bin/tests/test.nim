import os
import osproc
import strutils
import system
import unittest

const zipExt =
  when defined(windows): ".zip"
  else: ".tar.xz"

const distDir = (".."/"dist"/"nim_ci_test-" & hostOS & "_" & hostCPU).absolutePath
const binDir = (".."/"bin").absolutePath


suite "test":
  test "executables were built by nimble build":
    for bin in ["nim_ci_test_bin_1", "nim_ci_test_bin_2"]:
      let (output, exitCode) = execCmdEx(binDir/bin)
      check exitCode == 0
      check output.strip == bin

  test "executables were built and placed in dist directory by export_bin_artifacts":
    for bin in ["nim_ci_test_bin_1", "nim_ci_test_bin_2"]:
      let (output, exitCode) = execCmdEx(distDir/bin)
      check exitCode == 0
      check output.strip == bin

  test "executables were installed in PATH by nimble install":
    for bin in ["nim_ci_test_bin_1", "nim_ci_test_bin_2"]:
      let (output, exitCode) = execCmdEx("which " & bin)
      check exitCode == 0
      check output.strip notin [
        "",
        distDir/bin,
        binDir/bin,
      ]
    for bin in ["nim_ci_test_bin_1", "nim_ci_test_bin_2"]:
      let (output, exitCode) = execCmdEx(bin)
      check exitCode == 0
      check output.strip == bin

  test "zip is sane":
    removeDir("foo")
    let zipFile = distDir & zipExt
    let (output, exitCode) = execCmdEx("tar xf " & zipFile & " -C foo")
    check exitCode == 0
    check output.strip == ""
    check dirExists("foo")
    for bin in ["nim_ci_test_bin_1", "nim_ci_test_bin_2"]:
      let (output, exitCode) = execCmdEx("foo"/bin)
      check exitCode == 0
      check output.strip == bin
    removeDir("foo")