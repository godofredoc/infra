#!/usr/bin/env lucicfg
# Copyright 2019 The Flutter Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""
Configurations for the packages repository.

The schedulers pull commits indirectly from GoB repo (https://chromium.googlesource.com/external/github.com/flutter/flutter)
which is mirrored from https://github.com/flutter/flutter.
"""

load("//lib/common.star", "common")
load("//lib/repos.star", "repos")


def _setup():
    platform_args = {'linux': {'properties': {'fuchsia_ctl_version': None}}}
    packages_define_recipes()
    packages_try_config(platform_args)


def packages_define_recipes():
    # Defines recipes
    luci.recipe(
        name='fuchsia_ctl',
        cipd_package='flutter/recipe_bundles/flutter.googlesource.com/recipes',
        cipd_version='refs/heads/master',
    )


def packages_try_config(platform_args):
    # Defines a list view for try builders
    list_view_name = 'fuchsia_ctl-try'
    luci.list_view(
        name='fuchsia_ctl-try',
        title='fuchsia_ctl try builders',
    )

    # Defines cocoon try builders
    common.linux_try_builder(name='fuchsia_ctl|fctl',
                             recipe='fuchsia_ctl',
                             repo=repos.PACKAGES,
                             list_view_name='fuchsia_ctl-try',
                             **platform_args['linux'])


packages_config = struct(setup=_setup, )
