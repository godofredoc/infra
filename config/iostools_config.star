#!/usr/bin/env lucicfg
# Copyright 2020 The Flutter Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""
Configurations for ios_tool builders.

The schedulers pull commits indirectly from GoB repo (https://chromium.googlesource.com/external/github.com/flutter/flutter)
which is mirrored from https://github.com/flutter/flutter.
"""

load("//lib/common.star", "common")
load("//lib/consoles.star", "consoles")
load("//lib/repos.star", "repos")


def _setup():
    luci.recipe(
        name='ios-usb-dependencies',
        cipd_package='flutter/recipe_bundles/flutter.googlesource.com/recipes',
        cipd_version='refs/heads/master',
    )
    iostools_prod_config()


def ios_tools_builder(name, repo):
    builder = name.split('|')[0]
    consoles.console_view(builder, repo)
    luci.gitiles_poller(name='gitiles-trigger-%s' % builder,
                        bucket='prod',
                        repo=repo,
                        triggers=[builder])
    common.mac_prod_builder(
        name=name,
        repo=repo,
        recipe='ios-usb-dependencies',
        properties={
            'package_name': builder + '-flutter',
        },
        console_view_name=builder,
        triggering_policy=scheduler.greedy_batching(
            max_concurrent_invocations=1, max_batch_size=6),
    )


def iostools_prod_config():
    ios_tools_builder(name='ideviceinstaller|idev',
                      repo=repos.IDEVICEINSTALLER)
    ios_tools_builder(name='libimobiledevice|libi',
                      repo=repos.LIBIMOBILEDEVICE)
    ios_tools_builder(name='libplist|plist', repo=repos.LIBPLIST)
    ios_tools_builder(name='usbmuxd|usbmd', repo=repos.USBMUXD)
    ios_tools_builder(name='openssl|ssl', repo=repos.OPENSSL)
    ios_tools_builder(name='ios-deploy|deploy', repo=repos.IOS_DEPLOY)
    ios_tools_builder(name='libzip|zip', repo=repos.LIBZIP)


iostools_config = struct(setup=_setup, )
