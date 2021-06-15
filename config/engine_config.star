#!/usr/bin/env lucicfg
# Copyright 2020 The Flutter Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""
Configurations for the flutter engine repository.

The schedulers pull commits indirectly from GoB repo
(https://chromium.googlesource.com/external/github.com/flutter/engine)
which is mirrored from https://github.com/flutter/engine.

Try jobs use github directly but are also registered with luci-cq
to take advantage of led recipe builder tests.
"""

load("//lib/common.star", "common")
load("//lib/repos.star", "repos")
load("//lib/timeout.star", "timeout")

XCODE_VERSION = "11e708"

# A max of three different xcode versions will be used across all the flutter repositories.
# We will use "old_osx_sdk", "default_osx_sdk", and "new_osx_sdk" to reference them and avoid
# the caches to be overriden when the bots run tasks between engine and framework if the use the
# same named cache with diffferent version of xcode.
OLD_XCODE_CACHE_NAME = "old_osx_sdk"

def _setup(branches, fuchsia_ctl_version):
    """Default configurations for branches and repos."""
    platform_args = {
        "linux": {
            "caches": [
                # Allow disabling builder cache behavior in
                # buildbucket. Removing the default "builder" cache that buildbucket would
                # otherwise create with a 4 minute timeout preventing us from using any
                # swarming task slice <4 minutes.
                swarming.cache(path = "builder"),
            ],
            "os": "Linux",
        },
        "mac": {
            "caches": [
                swarming.cache(name = "flutter_cocoapods", path = "cocoapods"),
                # Installing osx_sdk on mac builders is slow.
                swarming.cache("osx_sdk", name = OLD_XCODE_CACHE_NAME),
                # Allow disabling builder cache behavior in
                # buildbucket. Removing the default "builder" cache that buildbucket would
                # otherwise create with a 4 minute timeout preventing us from using any
                # swarming task slice <4 minutes.
                swarming.cache(path = "builder"),
            ],
            "os": "Mac-10.15",
        },
        "windows": {
            "caches": [
                # Allow disabling builder cache behavior in
                # buildbucket. Removing the default "builder" cache that buildbucket would
                # otherwise create with a 4 minute timeout preventing us from using any
                # swarming task slice <4 minutes.
                swarming.cache(path = "builder"),
            ],
            "execution_timeout": timeout.XL,
            "os": "Windows-10",
        },
    }

    engine_recipes(branches.stable.version)
    engine_prod_config(
        platform_args,
        "stable",
        branches.stable.version,
        branches.stable.testing_ref,
        fuchsia_ctl_version,
    )

    engine_recipes(branches.beta.version)
    engine_prod_config(
        platform_args,
        "beta",
        branches.beta.version,
        branches.beta.testing_ref,
        fuchsia_ctl_version,
    )

    engine_recipes(branches.dev.version)
    engine_prod_config(
        platform_args,
        "dev",
        branches.dev.version,
        branches.dev.testing_ref,
        fuchsia_ctl_version,
    )

    engine_recipes(branches.master.version)
    engine_prod_config(
        platform_args,
        "master",
        branches.master.version,
        branches.master.testing_ref,
        fuchsia_ctl_version,
    )
    engine_prod_config(
        platform_args,
        "fuchsia_f1",
        branches.fuchsia_f1.version,
        branches.fuchsia_f1.testing_ref,
        fuchsia_ctl_version,
    )

    engine_try_config(platform_args, fuchsia_ctl_version)

def full_recipe_name(recipe_name, version):
    """Creates a recipe name for recipe and version.

    Args:
      recipe_name: This is a string with the recipe base name.
      version: A string with the build version. E.g. dev, beta, stable.

    Returns:
      A string with the recipe's full name.
    """
    return recipe_name if not version else "%s_%s" % (recipe_name, version)

def engine_recipes(version):
    """Creates a luci recipe for a given code version."""
    recipe_list = [
        "engine",
        "engine_unopt",
        "web_engine",
        "engine_builder",
        "femu_test",
        "engine/engine_arm",
        "engine/engine_metrics",
        "engine/framework_smoke",
        "engine/scenarios",
        "engine/web_engine_drone",
        "engine/web_engine_framework",
    ]
    for name in recipe_list:
        luci.recipe(
            name = full_recipe_name(name, version),
            cipd_package =
                "flutter/recipe_bundles/flutter.googlesource.com/recipes",
            cipd_version = "refs/heads/master",
            use_bbagent = True,
        )

def engine_properties(
        build_host = False,
        build_android_debug = False,
        build_android_aot = False,
        build_android_vulkan = False,
        build_ios = False,
        build_windows_uwp = False,
        needs_jazzy = False,
        ios_debug = False,
        ios_profile = False,
        ios_release = False,
        build_android_jit_release = False,
        no_bitcode = False,
        no_lto = False,
        framework = False,
        shard = "",
        subshards = [],
        gcs_goldens_bucket = "",
        fuchsia_ctl_version = ""):
    """Creates build properties for engine based on parameters.

    Args:
      build_host(boolean): Whether this is a host build or not.
      build_android_debug(boolean): Whether this is an android debug build or not.
      build_android_aot(boolean): Whether this is an android aot build or not.
      build_android_vulkan(boolean): Whether this a android vulkan build or not.
      build_ios(boolean): Whether to build ios or not.
      build_windows_uwp(boolean): Whether to build Windows UWP or not.
      needs_jazzy(boolean): True if this build needs jazzy.
      ios_debug(boolean): True if we need to build ios debug version.
      ios_profile(boolean): True if we need to build ios profile version.
      ios_release(booelan): True if we need to build ios release version.
      build_android_jit_release(boolean): True if we need to build android jit release version.
      no_bitcode(boolean): True if we need to disable bit code.
      no_lto(boolean): True if we want to build all binaries without LTO.
      framework(boolen): True if this build needs to use framework tests.
      shard(str): Name of the shard that framework unit tests will be triggered for. Eg: web_tests
      subshards(list): List of subshard names. Last one should have `_last` suffix. Eg: ["0", "1_last"],
      gcs_goldens_bucket: Bucket to upload failing golden tests' results for web engine.
      fuchsia_ctl_version(str): The version of the fuchsia controller to use.

    Returns:
      A dictionary with the properties applicable to the build, jazzy_version and fuchsia_ctl version.
    """
    properties = {
        "use_cas": True,
        "build_host": build_host,
        "build_fuchsia": True if fuchsia_ctl_version else False,
        "build_android_debug": build_android_debug,
        "build_android_aot": build_android_aot,
        "build_android_vulkan": build_android_vulkan,
        "build_ios": build_ios,
        "build_windows_uwp": build_windows_uwp,
        "build_android_jit_release": build_android_jit_release,
        "gcs_goldens_bucket": gcs_goldens_bucket,
        "$flutter/osx_sdk": {
            "sdk_version": XCODE_VERSION,
        },
    }
    if any([build_android_debug or build_android_aot or build_android_vulkan or build_android_jit_release]):
        properties["android_sdk_license"] = "\n24333f8a63b6825ea9c5514f83c2829b004d1fee"
        properties["android_sdk_preview_license"] = "\n84831b9409646a918e30573bab4c9c91346d8abd"
    if (no_lto):
        properties["no_lto"] = True
    if (build_ios):
        properties["ios_debug"] = ios_debug
        properties["ios_profile"] = ios_profile
        properties["ios_release"] = ios_release
        properties["no_bitcode"] = no_bitcode
    if (needs_jazzy):
        properties["jazzy_version"] = "0.9.5"
    if fuchsia_ctl_version:
        properties["fuchsia_ctl_version"] = fuchsia_ctl_version
    if (framework):
        properties["shard"] = shard
        properties["subshards"] = subshards
    return properties

def builder_name(pattern, branch):
    """Create a builder name using a string patter and branch."""
    return pattern % ("" if branch == "master" else " " + branch)

def engine_prod_config(platform_args, branch, version, ref, fuchsia_ctl_version):
    """Creates prod engine configurations.

    Args:
      platform_args(dict): Dictionary with the default properties with the platform
        as key.
      branch(str): The branch name to create configurations for.
      version(str): One of dev|stable|beta.
      ref(str): The git ref we are creating configurations for.
      fuchsia_ctl_version(str): The fuchsia controller version to use.
    """

    # Defines console views for prod builders
    console_view_name = ("engine" if branch == "master" else "%s_engine" %
                                                             branch)
    luci.console_view(
        name = console_view_name,
        repo = repos.ENGINE,
        refs = [ref],
    )

    # Defines prod schedulers
    trigger_name = branch + "-gitiles-trigger-engine"
    luci.gitiles_poller(
        name = trigger_name,
        bucket = "prod",
        repo = repos.ENGINE,
        refs = [ref],
    )

    # Defines triggering policy
    if branch == "master":
        triggering_policy = scheduler.greedy_batching(
            max_batch_size = 1,
            max_concurrent_invocations = 3,
        )
    else:
        triggering_policy = scheduler.greedy_batching(
            max_concurrent_invocations = 3,
        )

    # Defines master only builders
    if branch == "master":
        common.linux_prod_builder(
            name = builder_name("Linux%s benchmarks|lben", branch),
            recipe = full_recipe_name("engine/engine_metrics", version),
            properties = engine_properties(build_host = True),
            console_view_name = console_view_name,
            triggered_by = [trigger_name],
            triggering_policy = triggering_policy,
            priority = 30,
            **platform_args["linux"]
        )

    # Branch specific builders
    if branch == "fuchsia_f1":
        common.linux_prod_builder(
            name = builder_name("Linux%s Fuchsia|fsc", branch),
            recipe = full_recipe_name("engine", version),
            console_view_name = console_view_name,
            properties = engine_properties(fuchsia_ctl_version = fuchsia_ctl_version),
            triggered_by = [trigger_name],
            triggering_policy = triggering_policy,
            priority = 30 if branch == "master" else 25,
            execution_timeout = timeout.LONG,
            **platform_args["linux"]
        )

        # For specific branches we only create builders within the body of this if clause.
        return

    # Defines web engine prod builders
    common.linux_prod_builder(
        name = builder_name("Linux%s Web Engine|lwe", branch),
        recipe = full_recipe_name("web_engine", version),
        properties = engine_properties(gcs_goldens_bucket = "flutter_logs"),
        console_view_name = console_view_name,
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = 30 if branch == "master" else 25,
        **platform_args["linux"]
    )
    common.mac_prod_builder(
        name = builder_name("Mac%s Web Engine|mwe", branch),
        recipe = full_recipe_name("web_engine", version),
        properties = engine_properties(gcs_goldens_bucket = "flutter_logs"),
        console_view_name = console_view_name,
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = 30 if branch == "master" else 25,
        dimensions = {"mac_model": "Macmini8,1", "device_type": "none"},
        **platform_args["mac"]
    )
    common.windows_prod_builder(
        name = builder_name("Windows%s Web Engine|wwe", branch),
        recipe = full_recipe_name("web_engine", version),
        console_view_name = console_view_name,
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = 30 if branch == "master" else 25,
        dimensions = {"device_type": "none"},
        **platform_args["windows"]
    )
    common.linux_prod_builder(
        name = builder_name("Linux%s Web Drone|webdrn", branch),
        recipe = full_recipe_name("engine/web_engine_drone", version),
        properties = engine_properties(gcs_goldens_bucket = "flutter_logs"),
        console_view_name = None,
        no_notify = True,
        priority = 28 if branch == "master" else 25,
        **platform_args["linux"]
    )
    common.linux_prod_builder(
        name = builder_name("Linux%s Web Framework tests|web_tests", branch),
        recipe = full_recipe_name("engine/web_engine_framework", version),
        properties = engine_properties(
            framework = True,
            shard = "web_tests",
            subshards = ["0", "1", "2", "3", "4", "5", "6", "7_last"],
        ),
        console_view_name = console_view_name,
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = 30 if branch == "master" else 25,
        **platform_args["linux"]
    )

    # Defines engine Linux builders
    common.linux_prod_builder(
        name = builder_name("Linux%s Host Engine|host", branch),
        recipe = full_recipe_name("engine", version),
        console_view_name = console_view_name,
        properties = engine_properties(build_host = True),
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = 30 if branch == "master" else 25,
        **platform_args["linux"]
    )
    common.linux_prod_builder(
        name = builder_name("Linux%s Unopt|luopt", branch),
        recipe = full_recipe_name("engine_unopt", version),
        console_view_name = console_view_name,
        properties = engine_properties(),
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = 30 if branch == "master" else 25,
        **platform_args["linux"]
    )
    common.linux_prod_builder(
        name = builder_name("Linux%s Arm Host Engine|lah", branch),
        recipe = full_recipe_name("engine/engine_arm", version),
        console_view_name = console_view_name,
        properties = engine_properties(build_host = True),
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = 30 if branch == "master" else 25,
        execution_timeout = timeout.LONG,
        **platform_args["linux"]
    )
    common.linux_prod_builder(
        name = builder_name("Linux%s Fuchsia|fsc", branch),
        recipe = full_recipe_name("engine", version),
        console_view_name = console_view_name,
        properties = engine_properties(fuchsia_ctl_version = fuchsia_ctl_version),
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = 30 if branch == "master" else 25,
        execution_timeout = timeout.LONG,
        **platform_args["linux"]
    )

    common.linux_prod_builder(
        name = builder_name("Linux%s Fuchsia FEMU|femu", branch),
        recipe = full_recipe_name("femu_test", version),
        console_view_name = console_view_name,
        properties = engine_properties(fuchsia_ctl_version = fuchsia_ctl_version),
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = 30 if branch == "master" else 25,
        **platform_args["linux"]
    )
    common.linux_prod_builder(
        name = builder_name("Linux%s Android Debug Engine|dbg", branch),
        recipe = full_recipe_name("engine", version),
        console_view_name = console_view_name,
        properties = engine_properties(
            build_android_debug = True,
            build_android_vulkan = True,
            build_android_jit_release = True,
        ),
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = 30 if branch == "master" else 25,
        **platform_args["linux"]
    )
    common.linux_prod_builder(
        name = builder_name("Linux%s Android AOT Engine|aot", branch),
        recipe = full_recipe_name("engine", version),
        console_view_name = console_view_name,
        properties = engine_properties(build_android_aot = True),
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = 30 if branch == "master" else 25,
        **platform_args["linux"]
    )
    common.linux_prod_builder(
        name = builder_name("Linux%s Framework Smoke Tests|lfst", branch),
        recipe = full_recipe_name("engine/framework_smoke", version),
        console_view_name = console_view_name,
        properties = engine_properties(),
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = 30 if branch == "master" else 25,
        **platform_args["linux"]
    )
    common.linux_prod_builder(
        name = builder_name("Linux%s Engine Drone|drn", branch),
        recipe = full_recipe_name("engine_builder", version),
        console_view_name = None,
        no_notify = True,
        priority = 30 if branch == "master" else 25,
        **platform_args["linux"]
    )

    # Defines engine mac builders.
    common.mac_prod_builder(
        name = builder_name("Mac%s Host Engine|host", branch),
        recipe = full_recipe_name("engine", version),
        console_view_name = console_view_name,
        properties = engine_properties(build_host = True),
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = 30 if branch == "master" else 25,
        dimensions = {"mac_model": "Macmini8,1", "device_type": "none"},
        execution_timeout = timeout.MEDIUM_LONG,
        **platform_args["mac"]
    )
    common.mac_prod_builder(
        name = builder_name("Mac%s Unopt|muopt", branch),
        recipe = full_recipe_name("engine_unopt", version),
        console_view_name = console_view_name,
        properties = engine_properties(needs_jazzy = True),
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = 30 if branch == "master" else 25,
        dimensions = {"mac_model": "Macmini8,1", "device_type": "none"},
        execution_timeout = timeout.MEDIUM_LONG,
        **platform_args["mac"]
    )
    common.mac_prod_builder(
        name = builder_name("Mac%s Android Debug Engine|dbg", branch),
        recipe = full_recipe_name("engine", version),
        console_view_name = console_view_name,
        properties = engine_properties(
            build_android_debug = True,
            build_android_vulkan = True,
        ),
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = 30 if branch == "master" else 25,
        dimensions = {"mac_model": "Macmini8,1", "device_type": "none"},
        **platform_args["mac"]
    )
    common.mac_prod_builder(
        name = builder_name("Mac%s Android AOT Engine|aot", branch),
        recipe = full_recipe_name("engine", version),
        console_view_name = console_view_name,
        properties = engine_properties(build_android_aot = True),
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = 30 if branch == "master" else 25,
        dimensions = {"mac_model": "Macmini8,1", "device_type": "none"},
        **platform_args["mac"]
    )
    common.mac_prod_builder(
        name = builder_name("Mac%s iOS Engine|ios", branch),
        recipe = full_recipe_name("engine", version),
        console_view_name = console_view_name,
        properties = engine_properties(
            build_ios = True,
            ios_debug = True,
            needs_jazzy = True,
        ),
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = 30 if branch == "master" else 25,
        dimensions = {"mac_model": "Macmini8,1", "device_type": "none"},
        execution_timeout = timeout.LONG,
        **platform_args["mac"]
    )
    common.mac_prod_builder(
        name = builder_name("Mac%s iOS Engine Profile|ios", branch),
        recipe = full_recipe_name("engine", version),
        console_view_name = console_view_name,
        properties = engine_properties(
            build_ios = True,
            ios_profile = True,
            needs_jazzy = True,
        ),
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = 30 if branch == "master" else 25,
        dimensions = {"mac_model": "Macmini8,1", "device_type": "none"},
        execution_timeout = timeout.LONG,
        **platform_args["mac"]
    )
    common.mac_prod_builder(
        name = builder_name("Mac%s iOS Engine Release|ios", branch),
        recipe = full_recipe_name("engine", version),
        console_view_name = console_view_name,
        properties = engine_properties(
            build_ios = True,
            ios_release = True,
            needs_jazzy = True,
        ),
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = 30 if branch == "master" else 25,
        dimensions = {"mac_model": "Macmini8,1", "device_type": "none"},
        execution_timeout = timeout.LONG,
        **platform_args["mac"]
    )
    common.mac_prod_builder(
        name = builder_name("Mac%s Engine Drone|drn", branch),
        recipe = full_recipe_name("engine_builder", version),
        console_view_name = None,
        no_notify = True,
        priority = 30 if branch == "master" else 25,
        dimensions = {"device_type": "none"},
        **platform_args["mac"]
    )

    # Defines engine Windows builders
    common.windows_prod_builder(
        name = builder_name("Windows%s Host Engine|host", branch),
        recipe = full_recipe_name("engine", version),
        console_view_name = console_view_name,
        properties = engine_properties(build_host = True),
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = 30 if branch == "master" else 25,
        dimensions = {"device_type": "none"},
        **platform_args["windows"]
    )
    common.windows_prod_builder(
        name = builder_name("Windows%s Unopt|wuopt", branch),
        recipe = full_recipe_name("engine_unopt", version),
        console_view_name = console_view_name,
        properties = engine_properties(),
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = 30 if branch == "master" else 25,
        dimensions = {"device_type": "none"},
        **platform_args["windows"]
    )
    common.windows_prod_builder(
        name = builder_name("Windows%s UWP Engine|uwp", branch),
        recipe = full_recipe_name("engine", version),
        console_view_name = console_view_name,
        properties = engine_properties(build_windows_uwp = True),
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = 30 if branch == "master" else 25,
        dimensions = {"device_type": "none"},
        **platform_args["windows"]
    )
    common.windows_prod_builder(
        name = builder_name("Windows%s Android AOT Engine|aot", branch),
        recipe = full_recipe_name("engine", version),
        console_view_name = console_view_name,
        properties = engine_properties(build_android_aot = True),
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = 30 if branch == "master" else 25,
        dimensions = {"device_type": "none"},
        **platform_args["windows"]
    )
    common.windows_prod_builder(
        name = builder_name(
            "Windows%s Engine Drone|drn",
            branch,
        ),
        recipe = full_recipe_name(
            "engine_builder",
            version,
        ),
        console_view_name = None,
        no_notify = True,
        priority = 30 if branch == "master" else 25,
        **platform_args["windows"]
    )

def engine_try_config(platform_args, fuchsia_ctl_version):
    """Defines a list view for try builders.

    Args:
      platform_args(dict): Dictionary with default properties with
        platform as a key.
      fuchsia_ctl_version(str): The fuchsia controller version to use.
    """
    list_view_name = "engine-try"
    luci.list_view(
        name = "engine-try",
        title = "Engine try builders",
    )

    # Web Engine (all) try builders.
    common.linux_try_builder(
        name = "Linux Web Engine|lwe",
        recipe = "web_engine",
        repo = repos.ENGINE,
        add_cq = True,
        list_view_name = list_view_name,
        properties = engine_properties(
            gcs_goldens_bucket = "flutter_logs",
            no_lto = True,
        ),
        **platform_args["linux"]
    )
    common.mac_try_builder(
        name = "Mac Web Engine|mwe",
        recipe = "web_engine",
        repo = repos.ENGINE,
        list_view_name = list_view_name,
        properties = engine_properties(
            gcs_goldens_bucket = "flutter_logs",
            no_lto = True,
        ),
        dimensions = {"mac_model": "Macmini8,1", "device_type": "none"},
        **platform_args["mac"]
    )
    common.windows_try_builder(
        name = "Windows Web Engine|wwe",
        recipe = "web_engine",
        repo = repos.ENGINE,
        list_view_name = list_view_name,
        **platform_args["windows"]
    )
    common.linux_try_builder(
        name = "Linux Web Framework tests|web_tests",
        recipe = "engine/web_engine_framework",
        repo = repos.ENGINE,
        add_cq = True,
        list_view_name = list_view_name,
        properties = engine_properties(
            framework = True,
            shard = "web_tests",
            subshards = ["0", "1", "2", "3", "4", "5", "6", "7_last"],
        ),
        **platform_args["linux"]
    )
    common.linux_try_builder(
        name = "Linux Web Drone|webdrn",
        recipe = "engine/web_engine_drone",
        repo = repos.ENGINE,
        list_view_name = list_view_name,
        properties = engine_properties(
            gcs_goldens_bucket = "flutter_logs",
            no_lto = True,
        ),
        **platform_args["linux"]
    )

    # Engine Linux try builders.
    common.linux_try_builder(
        name = "Linux Host Engine|host",
        recipe = "engine",
        repo = repos.ENGINE,
        add_cq = True,
        list_view_name = list_view_name,
        properties = engine_properties(
            build_host = True,
            no_lto = True,
        ),
        **platform_args["linux"]
    )
    common.linux_try_builder(
        name = "Linux Unopt|luopt",
        recipe = "engine_unopt",
        repo = repos.ENGINE,
        add_cq = True,
        list_view_name = list_view_name,
        properties = engine_properties(
            no_lto = True,
        ),
        **platform_args["linux"]
    )
    common.linux_try_builder(
        name = "Linux Arm Host Engine|lah",
        recipe = "engine/engine_arm",
        repo = repos.ENGINE,
        add_cq = True,
        list_view_name = list_view_name,
        properties = engine_properties(
            build_host = True,
            no_lto = True,
        ),
        execution_timeout = timeout.LONG,
        **platform_args["linux"]
    )
    common.linux_try_builder(
        name = "Linux Fuchsia|fsc",
        recipe = "engine",
        repo = repos.ENGINE,
        add_cq = True,
        list_view_name = list_view_name,
        properties = engine_properties(
            fuchsia_ctl_version = fuchsia_ctl_version,
            no_lto = True,
        ),
        execution_timeout = timeout.LONG,
        **platform_args["linux"]
    )
    common.linux_try_builder(
        name = "Linux Fuchsia FEMU|femu",
        recipe = "femu_test",
        repo = repos.ENGINE,
        add_cq = True,
        list_view_name = list_view_name,
        properties = engine_properties(
            fuchsia_ctl_version = fuchsia_ctl_version,
            no_lto = True,
        ),
        **platform_args["linux"]
    )
    common.linux_try_builder(
        name = "Linux Android Debug Engine|dbg",
        recipe = "engine",
        repo = repos.ENGINE,
        add_cq = True,
        list_view_name = list_view_name,
        properties = engine_properties(
            build_android_debug = True,
            build_android_vulkan = True,
            no_lto = True,
        ),
        **platform_args["linux"]
    )
    common.linux_try_builder(
        name = "Linux Android AOT Engine|aot",
        recipe = "engine",
        repo = repos.ENGINE,
        add_cq = True,
        list_view_name = list_view_name,
        properties = engine_properties(
            build_android_aot = True,
            no_lto = True,
        ),
        **platform_args["linux"]
    )
    common.linux_try_builder(
        name = "Linux Android Scenarios|scnrs",
        recipe = "engine/scenarios",
        repo = repos.ENGINE,
        list_view_name = list_view_name,
        properties = {
            "upload_packages": True,
            "clobber": True,
        },
        **platform_args["linux"]
    )
    common.linux_try_builder(
        name = "Linux Framework Smoke Tests|lfst",
        recipe = "engine/framework_smoke",
        repo = repos.ENGINE,
        list_view_name = list_view_name,
        **platform_args["linux"]
    )
    common.linux_try_builder(
        name = "Linux Engine Drone|drn",
        recipe = "engine_builder",
        repo = repos.ENGINE,
        list_view_name = list_view_name,
        **platform_args["linux"]
    )

    # Engine Linux try builders.
    common.mac_try_builder(
        name = "Mac Host Engine|host",
        recipe = "engine",
        repo = repos.ENGINE,
        add_cq = True,
        list_view_name = list_view_name,
        properties = engine_properties(
            build_host = True,
            no_lto = True,
        ),
        dimensions = {"mac_model": "Macmini8,1", "device_type": "none"},
        **platform_args["mac"]
    )
    common.mac_try_builder(
        name = "Mac Unopt|muopt",
        recipe = "engine_unopt",
        repo = repos.ENGINE,
        add_cq = True,
        list_view_name = list_view_name,
        properties = engine_properties(
            needs_jazzy = True,
            no_lto = True,
        ),
        dimensions = {"mac_model": "Macmini8,1", "device_type": "none"},
        **platform_args["mac"]
    )
    common.mac_try_builder(
        name = "Mac Android Debug Engine|dbg",
        recipe = "engine",
        repo = repos.ENGINE,
        list_view_name = list_view_name,
        properties = engine_properties(
            build_android_debug = True,
            build_android_vulkan = True,
            no_lto = True,
        ),
        dimensions = {"mac_model": "Macmini8,1", "device_type": "none"},
        **platform_args["mac"]
    )
    common.mac_try_builder(
        name = "Mac Android AOT Engine|aot",
        recipe = "engine",
        repo = repos.ENGINE,
        list_view_name = list_view_name,
        properties = engine_properties(
            build_android_aot = True,
            no_lto = True,
        ),
        dimensions = {"mac_model": "Macmini8,1", "device_type": "none"},
        **platform_args["mac"]
    )
    common.mac_try_builder(
        name = "Mac iOS Engine|ios",
        recipe = "engine",
        repo = repos.ENGINE,
        list_view_name = list_view_name,
        properties = engine_properties(
            build_ios = True,
            ios_debug = True,
            needs_jazzy = True,
            no_bitcode = True,
            no_lto = True,
        ),
        dimensions = {"mac_model": "Macmini8,1", "device_type": "none"},
        **platform_args["mac"]
    )
    common.mac_try_builder(
        name = "Mac Engine Drone|drn",
        recipe = "engine_builder",
        repo = repos.ENGINE,
        list_view_name = list_view_name,
        dimensions = {"device_type": "none"},
        **platform_args["mac"]
    )

    # Engine Windows try builders.
    common.windows_try_builder(
        name = "Windows Host Engine|host",
        recipe = "engine",
        repo = repos.ENGINE,
        add_cq = True,
        list_view_name = list_view_name,
        properties = engine_properties(
            build_host = True,
            no_lto = True,
        ),
        **platform_args["windows"]
    )
    common.windows_try_builder(
        name = "Windows Unopt|wunopt",
        recipe = "engine_unopt",
        repo = repos.ENGINE,
        add_cq = True,
        list_view_name = list_view_name,
        properties = engine_properties(
            no_lto = True,
        ),
        **platform_args["windows"]
    )
    common.windows_try_builder(
        name = "Windows UWP Engine|uwp",
        recipe = "engine",
        repo = repos.ENGINE,
        list_view_name = list_view_name,
        properties = engine_properties(
            build_windows_uwp = True,
            no_lto = True,
        ),
        **platform_args["windows"]
    )
    common.windows_try_builder(
        name = "Windows Android AOT Engine|aot",
        recipe = "engine",
        repo = repos.ENGINE,
        list_view_name = list_view_name,
        properties = engine_properties(
            build_android_aot = True,
            no_lto = True,
        ),
        **platform_args["windows"]
    )
    common.windows_try_builder(
        name = "Windows Engine Drone|drn",
        recipe = "engine_builder",
        repo = repos.ENGINE,
        list_view_name = list_view_name,
        **platform_args["windows"]
    )

engine_config = struct(setup = _setup)
