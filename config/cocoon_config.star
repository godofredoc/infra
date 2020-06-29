#!/usr/bin/env lucicfg
# Copyright 2019 The Flutter Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""
Configurations for the cocoon repository.

The schedulers pull commits indirectly from GoB repo (https://chromium.googlesource.com/external/github.com/flutter/flutter)
which is mirrored from https://github.com/flutter/flutter.
"""

load("//lib/common.star", "common")
load("//lib/repos.star", "repos")


def _setup():
    platform_args = {
        'linux': {
            'caches':
            [swarming.cache(name='dart_pub_cache', path='.pub-cache')]
        }
    }
    cocoon_define_recipes()
    cocoon_try_config(platform_args)


def cocoon_define_recipes():
    # Defines recipes
    luci.recipe(
        name='cocoon',
        cipd_package='flutter/recipe_bundles/flutter.googlesource.com/recipes',
        cipd_version='refs/heads/master',
    )


def cocoon_try_config(platform_args):
    # Defines a list view for try builders
    list_view_name = 'cocoon-try'
    luci.list_view(
        name=list_view_name,
        title='Cocoon try builders',
    )
    # Defines cocoon try builders
    common.linux_try_builder(name='Cocoon|cocoon',
                             recipe='cocoon',
                             list_view_name=list_view_name,
                             repo=repos.COCOON,
                             **platform_args['linux'])


cocoon_config = struct(setup=_setup, )
