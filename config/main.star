#!/usr/bin/env lucicfg
# Copyright 2019 The Flutter Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""
LUCI project configuration for the production instance of LUCI.

After modifying this file execute it ('./main.star') to regenerate the configs.

This file uses a Python-like syntax known as Starlark:
https://docs.bazel.build/versions/master/skylark/language.html

The documentation for lucicfg can be found here:
https://chromium.googlesource.com/infra/luci/luci-go/+/refs/heads/master/lucicfg/doc/README.md
"""

load("//lib/common.star", "common")
load("//lib/consoles.star", "consoles")
load("//lib/helpers.star", "helpers")
load("//lib/repos.star", "repos")
load("//lib/recipes.star", "recipes")
load("//cocoon_config.star", "cocoon_config")
load("//recipes_config.star", "recipes_config")
load("//engine_config.star", "engine_config")
load("//framework_config.star", "framework_config")
load("//iostools_config.star", "iostools_config")
load("//packages_config.star", "packages_config")
load("//packaging_config.star", "packaging_config")

# Avoid jumping back and forth with configs being updated by lower
# version lucicfg.
lucicfg.check_version('1.15.0')

BRANCHES = {
    'stable': {
        'ref': r'refs/heads/flutter-1\.17-candidate\.3',
        # To be interpolated into recipe names e.g. 'flutter/flutter_' + BRANCHES['stable']['version']
        'version': 'v1_17_0',
    },
    'beta': {
        'ref': r'refs/heads/flutter-1\.19-candidate\..+',
        'version': None,
    },
    'dev': {
        # Don't match the last number of the branch name or else this will have
        # to be updated for every dev release.
        'ref': r'refs/heads/flutter-1\.20-candidate\..+',
        'version': None,
    },
    'master': {
        'ref': r'refs/heads/master',
        'version': None,
    },
}

FUCHSIA_CTL_VERSION = 'version:0.0.23'

lucicfg.config(config_dir="generated/flutter",
               tracked_files=["**/*"],
               fail_on_warnings=True)

luci.project(
    name='flutter',
    config_dir="luci",
    buildbucket='cr-buildbucket.appspot.com',
    logdog='luci-logdog.appspot.com',
    milo='luci-milo.appspot.com',
    scheduler='luci-scheduler.appspot.com',
    swarming='chromium-swarm.appspot.com',
    notify='luci-notify.appspot.com',
    acls=[
        acl.entry(
            roles=[
                acl.BUILDBUCKET_READER,
                acl.LOGDOG_READER,
                acl.PROJECT_CONFIGS_READER,
                acl.SCHEDULER_READER,
            ],
            groups='all',
        ),
        acl.entry(
            roles=[
                acl.BUILDBUCKET_TRIGGERER,
                acl.SCHEDULER_TRIGGERER,
            ],
            groups='project-flutter-prod-schedulers',
        ),
        acl.entry(
            roles=[
                acl.BUILDBUCKET_OWNER,
                acl.SCHEDULER_OWNER,
            ],
            groups='project-flutter-admins',
        ),
        acl.entry(
            acl.LOGDOG_WRITER,
            groups='luci-logdog-chromium-writers',
        ),
        acl.entry(
            roles=[acl.CQ_COMMITTER, acl.CQ_DRY_RUNNER],
            groups=["project-flutter-try-schedulers"],
        ),
    ],
)

luci.logdog(gs_bucket='chromium-luci-logdog')

luci.milo(
    logo=
    'https://storage.googleapis.com/chrome-infra-public/logo/flutter-logo.svg',
    favicon='https://storage.googleapis.com/flutter_infra/favicon.ico',
)

luci.bucket(
    name='prod',
    acls=[
        acl.entry(acl.BUILDBUCKET_TRIGGERER,
                  groups='project-flutter-prod-schedulers'),
        acl.entry(acl.SCHEDULER_TRIGGERER,
                  groups='project-flutter-prod-schedulers'),
    ],
)

luci.bucket(
    name='try',
    acls=[
        acl.entry(acl.BUILDBUCKET_TRIGGERER,
                  groups='project-flutter-try-schedulers')
    ],
)

# CQ group configurations. Only FLUTTER_RECIPES is using
# LUCI CQ but we still need the CQ configurations for all
# the try configurations for led recipe tests.
common.cq_group(repos.COCOON)
common.cq_group(repos.ENGINE)
common.cq_group(repos.FLUTTER)
common.cq_group(repos.FLUTTER_RECIPES)
common.cq_group(repos.PACKAGES)

luci.builder.defaults.dimensions.set({
    "cpu": common.TARGET_X64,
    "os": "Linux",
})

luci.builder.defaults.properties.set({
    '$kitchen': {
        'emulate_gce': True
    },
    '$build/goma': {
        'use_luci_auth': True
    },
    '$recipe_engine/isolated': {
        "server": "https://isolateserver.appspot.com"
    },
    '$recipe_engine/swarming': {
        "server": "https://chromium-swarm.appspot.com"
    },
    'mastername':
    'client.flutter',
    'goma_jobs':
    '200',
    'android_sdk_license':
    '\n24333f8a63b6825ea9c5514f83c2829b004d1fee',
    'android_sdk_preview_license':
    '\n84831b9409646a918e30573bab4c9c91346d8abd',
})

############################ End Global Defaults ############################
cocoon_config.setup()

engine_config.setup(BRANCHES)

framework_config.setup(BRANCHES)

iostools_config.setup()

packages_config.setup()

packaging_config.setup(BRANCHES)

recipes_config.setup()
######################### Console Definitions #################################
