#!/usr/bin/env lucicfg
# Copyright 2019 The Flutter Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""
Configurations for packaging builders.

The schedulers pull commits indirectly from GoB repo (https://chromium.googlesource.com/external/github.com/flutter/flutter)
which is mirrored from https://github.com/flutter/flutter.
"""

load("//lib/common.star", "common")
load("//lib/repos.star", "repos")


def _setup(branches):
    platform_args = {
        'linux': {
            'properties': {},
        },
        'mac': {
            'properties': {},
        },
        'windows': {
            'properties': {},
        },
    }

    packaging_recipe('ios-usb-dependencies', '')
    for branch in branches:
        # Skip packaging for master branch.
        if branch == 'master':
            continue
        packaging_recipe('flutter', branches[branch]['version'])
        packaging_prod_config(
            platform_args,
            branch,
            branches[branch]['version'],
            branches[branch]['ref'],
        )


def recipe_name(name, version):
    return '%s%s' % (name, '_%s' % version if version else '')


def builder_name(pattern, branch):
    return pattern % (branch.capitalize(), branch)


def packaging_recipe(name, version):
    luci.recipe(
        name=recipe_name(name, version),
        cipd_package='flutter/recipe_bundles/flutter.googlesource.com/recipes',
        cipd_version='refs/heads/master',
    )


def packaging_prod_config(platform_args, branch, version, ref):

    #console_names = struct(packaging=consoles.console_view(
    #    'packaging',
    #    repos.FLUTTER,
    #    refs=['refs/heads/beta', 'refs/heads/dev', 'refs/heads/stable'],
    #    exclude_ref='refs/heads/master',
    #), )
    #
    #def ios_tools_builder(**kwargs):
    #    builder = kwargs['name'].split('|')[0]
    #    repo = 'https://flutter-mirrors.googlesource.com/' + builder
    #    consoles.console_view(builder, repo)
    #    luci.gitiles_poller(name='gitiles-trigger-' + builder,
    #                        bucket='prod',
    #                        repo=repo,
    #                        triggers=[builder])
    #    return common.mac_prod_builder(recipe='ios-usb-dependencies',
    #                                   properties={
    #                                       'package_name': builder + '-flutter',
    #                                   },
    #                                   console_view_name=builder,
    #                                   triggering_policy=scheduler.greedy_batching(
    #                                       max_concurrent_invocations=1,
    #                                       max_batch_size=6),
    #                                   **kwargs)
    #
    #ios_tools_builder(name='ideviceinstaller|idev')
    #ios_tools_builder(name='libimobiledevice|libi')
    #ios_tools_builder(name='libplist|plist')
    #ios_tools_builder(name='usbmuxd|usbmd')
    #ios_tools_builder(name='openssl|ssl')
    #ios_tools_builder(name='ios-deploy|deploy')
    #ios_tools_builder(name='libzip|zip')

    # Defines console views for prod builders
    console_view_name = ('packaging'
                         if branch == 'master' else '%s_packaging' % branch)
    luci.console_view(
        name=console_view_name,
        repo=repos.FLUTTER,
        refs=[ref],
    )

    # Defines prod schedulers
    trigger_name = branch + '-gitiles-trigger-framework'
    luci.gitiles_poller(
        name=trigger_name,
        bucket='prod',
        repo=repos.FLUTTER,
        refs=[ref],
    )

    # Defines triggering policy
    if branch == 'master':
        triggering_policy = scheduler.greedy_batching(
            max_concurrent_invocations=6)
    else:
        triggering_policy = scheduler.greedy_batching(
            max_batch_size=1, max_concurrent_invocations=3)

    # Defines framework prod builders
    common.linux_prod_builder(
        name=builder_name('Linux Flutter %s Packaging|%s', branch),
        recipe=recipe_name('flutter', version),
        console_view_name=console_view_name,
        triggered_by=[trigger_name],
        triggering_policy=triggering_policy,
        **platform_args['linux'],
    )
    common.mac_prod_builder(
        name=builder_name('Mac Flutter %s Packaging|%s', branch),
        recipe=recipe_name('flutter', version),
        console_view_name=console_view_name,
        triggered_by=[trigger_name],
        triggering_policy=triggering_policy,
        **platform_args['mac'],
    )
    common.windows_prod_builder(
        name=builder_name('Windows Flutter %s Packaging|%s', branch),
        recipe=recipe_name('flutter', version),
        console_view_name=console_view_name,
        triggered_by=[trigger_name],
        triggering_policy=triggering_policy,
        **platform_args['windows'],
    )


packaging_config = struct(setup=_setup, )
