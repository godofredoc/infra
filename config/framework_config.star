#!/usr/bin/env lucicfg
# Copyright 2019 The Flutter Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""
Configurations for the framework repository.

The schedulers pull commits indirectly from GoB repo (https://chromium.googlesource.com/external/github.com/flutter/flutter)
which is mirrored from https://github.com/flutter/flutter.
"""

load("//lib/common.star", "common")
load("//lib/repos.star", "repos")

# Global xcode versions.
XCODE_VERSION = "12c33"

# Global OS variables
LINUX_OS = "Linux"
WINDOWS_OS = "Windows-10"
MAC_OS = "Mac-10.15"

# Linux caches
LINUX_DEFAULT_CACHES = [
    # Android SDK
    swarming.cache(name = "android_sdk", path = "android"),
    # Chrome
    swarming.cache(name = "chrome_and_driver", path = "chrome"),
    # OpenJDK
    swarming.cache(name = "openjdk", path = "java"),
    # PubCache
    swarming.cache(name = "pub_cache", path = ".pub-cache"),
    # Flutter SDK code
    swarming.cache(name = "flutter_sdk", path = "flutter sdk"),
]

# Mac caches
MAC_CORE_CACHES = [
    # Android SDK
    swarming.cache(name = "android_sdk", path = "android"),
    # Chrome
    swarming.cache(name = "chrome_and_driver", path = "chrome"),
    # OpenJDK
    swarming.cache(name = "openjdk", path = "java"),
    # PubCache
    swarming.cache(name = "pub_cache", path = ".pub-cache"),
    # Flutter SDK code
    swarming.cache(name = "flutter_sdk", path = "flutter sdk"),
    # Xcode
    swarming.cache("xcode_binary"),
]

# This is to support two versions of xcode efficiently.
MAC_DEFAULT_CACHES = MAC_CORE_CACHES + [swarming.cache(name = "osx_sdk", path = "osx_sdk")]
MAC_NEWXCODE_CACHES = MAC_CORE_CACHES + [swarming.cache(name = "new_osx_sdk", path = "osx_sdk")]

# Windows caches
WIN_DEFAULT_CACHES = [
    # Android SDK
    swarming.cache(name = "android_sdk", path = "android"),
    # Chrome
    swarming.cache(name = "chrome_and_driver", path = "chrome"),
    # OpenJDK
    swarming.cache(name = "openjdk", path = "java"),
    # PubCache
    swarming.cache(name = "pub_cache", path = ".pub-cache"),
    # Flutter SDK code
    swarming.cache(name = "flutter_sdk", path = "flutter sdk"),
    # Visual Studio
    swarming.cache(name = "vsbuild", path = "vsbuild"),
]

def _setup(branches):
    framework_prod_config(
        "stable",
        branches.stable.version,
        branches.stable.testing_ref,
        branches.stable.release_ref,
    )
    framework_prod_config(
        "beta",
        branches.beta.version,
        branches.beta.testing_ref,
        branches.beta.release_ref,
    )
    framework_prod_config(
        "dev",
        branches.dev.version,
        branches.dev.testing_ref,
        branches.dev.release_ref,
    )
    framework_prod_config(
        "master",
        branches.master.version,
        branches.master.testing_ref,
        branches.master.release_ref,
    )

    framework_try_config()

def framework_prod_config(branch, version, testing_ref, release_ref):
    """Prod configurations for the framework repository.

    Args:
      branch(str): The branch name we are creating configurations for.
      version(str): One of dev|beta|stable.
      testing_ref(str): The git ref we are creating configurations for.
      release_ref(str): The git ref used for releases.
    """

    # TODO(godofredoc): Merge the recipe names once we remove the old one.
    recipe_name = ("flutter_" + version if version else "flutter")
    new_recipe_name = ("flutter/flutter_" + version if version else "flutter/flutter")
    drone_recipe_name = ("flutter/flutter_drone_" + version if version else "flutter/flutter_drone")
    luci.recipe(
        name = recipe_name,
        cipd_package = "flutter/recipe_bundles/flutter.googlesource.com/recipes",
        cipd_version = "refs/heads/master",
        use_bbagent = True,
    )
    luci.recipe(
        name = new_recipe_name,
        cipd_package = "flutter/recipe_bundles/flutter.googlesource.com/recipes",
        cipd_version = "refs/heads/master",
        use_bbagent = True,
    )
    luci.recipe(
        name = drone_recipe_name,
        cipd_package = "flutter/recipe_bundles/flutter.googlesource.com/recipes",
        cipd_version = "refs/heads/master",
        use_bbagent = True,
    )
    luci.recipe(
        name = "devicelab",
        cipd_package = "flutter/recipe_bundles/flutter.googlesource.com/recipes",
        cipd_version = "refs/heads/master",
        use_bbagent = True,
    )

    # Defines console views for prod builders
    console_view_name = ("framework" if branch == "master" else "%s_framework" % branch)
    luci.console_view(
        name = console_view_name,
        repo = repos.FLUTTER,
        refs = [testing_ref],
    )

    # Defines prod schedulers
    trigger_name = branch + "-gitiles-trigger-framework"
    luci.gitiles_poller(
        name = trigger_name,
        bucket = "prod",
        repo = repos.FLUTTER,
        refs = [testing_ref],
    )

    # Defines triggering policy
    if branch == "master":
        triggering_policy = scheduler.greedy_batching(
            max_batch_size = 3,
            max_concurrent_invocations = 3,
        )
    else:
        triggering_policy = scheduler.greedy_batching(
            max_batch_size = 1,
            max_concurrent_invocations = 3,
        )

    # Defines build priority, release builds should be prioritized.
    priority = 30 if branch == "master" else 29

    # Binaries are not signed on master
    if branch in ("stable", "beta", "dev"):
        common.mac_prod_builder(
            name = "Mac %s verify_binaries_codesigned|vbcs" % branch,
            recipe = new_recipe_name,
            console_view_name = console_view_name,
            triggered_by = [trigger_name],
            triggering_policy = scheduler.greedy_batching(
                max_batch_size = 50,
                max_concurrent_invocations = 3,
            ),
            priority = priority,
            properties = {
                "validation": "verify_binaries_codesigned",
                "validation_name": "Verify binaries codesigned",
                "dependencies": [{"dependency": "xcode"}],
                "$flutter/osx_sdk": {
                    "sdk_version": XCODE_VERSION,
                },
                "use_cas": True,
            },
            caches = [
                swarming.cache(name = "pub_cache", path = ".pub_cache"),
            ],
            os = MAC_OS,
        )

    # Linux platform sharded tests
    common.builder_with_subshards(
        name = "Linux%s build_tests|bld_tests" % ("" if branch == "master" else " " + branch),
        recipe = drone_recipe_name,
        console_view_name = console_view_name,
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = priority,
        properties = {
            "shard": "build_tests",
            "subshards": ["1_2", "2_2"],
            "use_cas": True,
            "dependencies": [{"dependency": "android_sdk"}, {"dependency": "chrome_and_driver"}, {"dependency": "open_jdk"}, {"dependency": "goldctl"}, {"dependency": "clang"}, {"dependency": "cmake"}, {"dependency": "ninja"}, {"dependency": "curl"}],
        },
        caches = LINUX_DEFAULT_CACHES,
        os = LINUX_OS,
        bucket = "prod",
        branch_name = "" if branch == "master" else " " + branch,
    )
    common.builder_with_subshards(
        name = "Linux%s framework_tests|frwk_tests" % ("" if branch == "master" else " " + branch),
        recipe = drone_recipe_name,
        console_view_name = console_view_name,
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = priority,
        properties = {
            "shard": "framework_tests",
            "subshards": ["libraries", "misc", "widgets"],
            "dependencies": [{"dependency": "goldctl"}, {"dependency": "curl"}],
            "use_cas": True,
        },
        caches = LINUX_DEFAULT_CACHES,
        os = LINUX_OS,
        bucket = "prod",
        branch_name = "" if branch == "master" else " " + branch,
    )
    common.builder_with_subshards(
        name = "Linux%s tool_tests|tool_tests" % ("" if branch == "master" else " " + branch),
        recipe = drone_recipe_name,
        console_view_name = console_view_name,
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = priority,
        properties = {
            "shard": "tool_tests",
            "subshards": ["general", "commands"],
            "dependencies": [{"dependency": "android_sdk"}, {"dependency": "open_jdk"}, {"dependency": "curl"}],
            "use_cas": True,
        },
        caches = LINUX_DEFAULT_CACHES,
        os = LINUX_OS,
        bucket = "prod",
        branch_name = "" if branch == "master" else " " + branch,
    )
    common.builder_with_subshards(
        name = "Linux%s tool_integration_tests|tool_tests_int" % ("" if branch == "master" else " " + branch),
        recipe = drone_recipe_name,
        console_view_name = console_view_name,
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = priority,
        properties = {
            "shard": "tool_integration_tests",
            "subshards": ["1_4", "2_4", "3_4", "4_4"],
            "dependencies": [{"dependency": "android_sdk"}, {"dependency": "chrome_and_driver"}, {"dependency": "open_jdk"}, {"dependency": "goldctl"}, {"dependency": "curl"}],
            "test_timeout_secs": 45 * 60,  # 45 mins test timeout.
            "use_cas": True,
        },
        caches = LINUX_DEFAULT_CACHES,
        os = LINUX_OS,
        bucket = "prod",
        branch_name = "" if branch == "master" else " " + branch,
    )
    common.linux_prod_builder(
        name = "Linux%s web_tool_tests|web_tt" % ("" if branch == "master" else " " + branch),
        recipe = drone_recipe_name,
        console_view_name = console_view_name,
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = priority,
        properties = {
            "shard": "web_tool_tests",
            "subshard": "web",
            "dependencies": [{"dependency": "android_sdk"}, {"dependency": "chrome_and_driver"}, {"dependency": "open_jdk"}, {"dependency": "goldctl"}, {"dependency": "curl"}],
            "use_cas": True,
        },
        caches = LINUX_DEFAULT_CACHES,
        os = LINUX_OS,
    )
    common.builder_with_subshards(
        name = "Linux%s web_tests|web_tests" % ("" if branch == "master" else " " + branch),
        recipe = drone_recipe_name,
        console_view_name = console_view_name,
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = priority,
        properties = {
            "shard": "web_tests",
            "subshards": ["0", "1", "2", "3", "4", "5", "6", "7_last"],
            "dependencies": [{"dependency": "android_sdk"}, {"dependency": "chrome_and_driver"}, {"dependency": "goldctl"}, {"dependency": "curl"}],
            "use_cas": True,
        },
        caches = LINUX_DEFAULT_CACHES,
        os = LINUX_OS,
        bucket = "prod",
        branch_name = "" if branch == "master" else " " + branch,
    )
    common.builder_with_subshards(
        name = "Linux%s web_long_running_tests|web_lrt" % ("" if branch == "master" else " " + branch),
        recipe = drone_recipe_name,
        console_view_name = console_view_name,
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        properties = {
            "shard": "web_long_running_tests",
            "subshards": ["1_5", "2_5", "3_5", "4_5", "5_5"],
            "dependencies": [{"dependency": "android_sdk"}, {"dependency": "chrome_and_driver"}, {"dependency": "goldctl"}, {"dependency": "curl"}],
            "use_cas": True,
        },
        caches = LINUX_DEFAULT_CACHES,
        os = LINUX_OS,
        bucket = "prod",
        branch_name = "" if branch == "master" else " " + branch,
    )
    common.linux_prod_builder(
        name = "Linux%s SDK Drone|frwdrn" % ("" if branch == "master" else " " + branch),
        recipe = drone_recipe_name,
        console_view_name = None,
        no_notify = True,
        caches = LINUX_DEFAULT_CACHES,
        os = LINUX_OS,
    )

    # Linux platform adhoc tests
    common.linux_prod_builder(
        name = "Linux%s analyze|anlz" % ("" if branch == "master" else " " + branch),
        recipe = new_recipe_name,
        console_view_name = console_view_name,
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = priority,
        properties = {
            "validation": "analyze",
            "validation_name": "Analyze",
            "dependencies": [{"dependency": "curl"}],
            "use_cas": True,
        },
        caches = LINUX_DEFAULT_CACHES,
        os = LINUX_OS,
    )
    common.linux_prod_builder(
        name = "Linux%s validate_ci_config|ci_cfg" % ("" if branch == "master" else " " + branch),
        recipe = new_recipe_name,
        console_view_name = console_view_name,
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = priority,
        properties = {
            "validation": "validate_ci_config",
            "validation_name": "Validate CI config",
            "dependencies": [{"dependency": "cocoon"}],
            "use_cas": True,
        },
        caches = LINUX_DEFAULT_CACHES,
        os = LINUX_OS,
    )
    common.linux_prod_builder(
        name = "Linux%s customer_testing|cst_test" % ("" if branch == "master" else " " + branch),
        recipe = new_recipe_name,
        console_view_name = console_view_name,
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = priority,
        properties = {
            "validation": "customer_testing",
            "validation_name": "Customer testing",
            "dependencies": [{"dependency": "curl"}],
            "use_cas": True,
        },
        caches = LINUX_DEFAULT_CACHES,
        os = LINUX_OS,
    )
    common.linux_prod_builder(
        name = "Linux%s docs_test|docs" % ("" if branch == "master" else " " + branch),
        recipe = new_recipe_name,
        console_view_name = console_view_name,
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = priority,
        properties = {
            "validation": "docs",
            "validation_name": "Docs",
            "dependencies": [{"dependency": "dashing"}, {"dependency": "curl"}],
            # Test only, the following two keys should be blank, only required
            # for publishing docs.
            "firebase_project": "",
            "release_ref": "",
            "use_cas": True,
        },
        caches = LINUX_DEFAULT_CACHES,
        os = LINUX_OS,
    )
    common.linux_prod_builder(
        name = "Linux%s fuchsia_precache|pcache" % ("" if branch == "master" else " " + branch),
        recipe = new_recipe_name,
        console_view_name = console_view_name,
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = priority,
        properties = {
            "validation": "fuchsia_precache",
            "validation_name": "Fuchsia precache",
            "dependencies": [{"dependency": "curl"}],
            "use_cas": True,
        },
        caches = LINUX_DEFAULT_CACHES,
        os = LINUX_OS,
    )
    common.linux_prod_builder(
        name = "Linux%s flutter_plugins|fltplgns" % ("" if branch == "master" else " " + branch),
        recipe = drone_recipe_name,
        console_view_name = console_view_name,
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = priority,
        properties = {
            "shard": "flutter_plugins",
            "subshard": "analyze",
            "dependencies": [{"dependency": "curl"}],
            "use_cas": True,
        },
        caches = LINUX_DEFAULT_CACHES,
        os = LINUX_OS,
    )
    if branch == "master":
        common.linux_prod_builder(
            name = "Linux%s skp_generator|skp_gen" % ("" if branch == "master" else " " + branch),
            recipe = drone_recipe_name,
            console_view_name = console_view_name,
            triggered_by = [trigger_name],
            triggering_policy = triggering_policy,
            priority = priority,
            properties = {
                "shard": "skp_generator",
                "subshard": "0",
                "dependencies": [{"dependency": "curl"}],
                "use_cas": True,
            },
            caches = LINUX_DEFAULT_CACHES,
            os = LINUX_OS,
        )

    # Windows platform
    common.builder_with_subshards(
        name = "Windows%s build_tests|bld_tests" % ("" if branch == "master" else " " + branch),
        recipe = drone_recipe_name,
        console_view_name = console_view_name,
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = priority,
        properties = {
            "shard": "build_tests",
            "subshards": ["1_3", "2_3", "3_3"],
            "dependencies": [{"dependency": "android_sdk"}, {"dependency": "chrome_and_driver"}, {"dependency": "open_jdk"}, {"dependency": "goldctl"}, {"dependency": "certs"}, {"dependency": "vs_build"}],
            "use_cas": True,
        },
        caches = WIN_DEFAULT_CACHES,
        os = WINDOWS_OS,
        bucket = "prod",
        branch_name = "" if branch == "master" else " " + branch,
    )
    common.builder_with_subshards(
        name = "Windows%s framework_tests|frwk_tests" % ("" if branch == "master" else " " + branch),
        recipe = drone_recipe_name,
        console_view_name = console_view_name,
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = priority,
        properties = {
            "shard": "framework_tests",
            "subshards": ["libraries", "misc", "widgets"],
            "dependencies": [{"dependency": "goldctl"}, {"dependency": "certs"}],
            "use_cas": True,
        },
        caches = WIN_DEFAULT_CACHES,
        os = WINDOWS_OS,
        bucket = "prod",
        branch_name = "" if branch == "master" else " " + branch,
    )
    common.builder_with_subshards(
        name = "Windows%s tool_tests|tool_tests" % ("" if branch == "master" else " " + branch),
        recipe = drone_recipe_name,
        console_view_name = console_view_name,
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = priority,
        properties = {
            "shard": "tool_tests",
            "subshards": ["general", "commands"],
            "dependencies": [{"dependency": "android_sdk"}, {"dependency": "open_jdk"}, {"dependency": "certs"}],
            "use_cas": True,
        },
        caches = WIN_DEFAULT_CACHES,
        os = WINDOWS_OS,
        bucket = "prod",
        branch_name = "" if branch == "master" else " " + branch,
    )
    common.builder_with_subshards(
        name = "Windows%s tool_integration_tests|tool_tests_int" % ("" if branch == "master" else " " + branch),
        recipe = drone_recipe_name,
        console_view_name = console_view_name,
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = priority,
        properties = {
            "shard": "tool_integration_tests",
            "subshards": ["1_5", "2_5", "3_5", "4_5", "5_5"],
            "dependencies": [{"dependency": "android_sdk"}, {"dependency": "chrome_and_driver"}, {"dependency": "open_jdk"}, {"dependency": "goldctl"}, {"dependency": "certs"}, {"dependency": "vs_build"}],
            "use_cas": True,
        },
        caches = WIN_DEFAULT_CACHES,
        os = WINDOWS_OS,
        bucket = "prod",
        branch_name = "" if branch == "master" else " " + branch,
    )
    common.windows_prod_builder(
        name = "Windows%s web_tool_tests|web_tt" % ("" if branch == "master" else " " + branch),
        recipe = drone_recipe_name,
        console_view_name = console_view_name,
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = priority,
        properties = {
            "shard": "web_tool_tests",
            "subshard": "web",
            "dependencies": [{"dependency": "android_sdk"}, {"dependency": "chrome_and_driver"}, {"dependency": "open_jdk"}, {"dependency": "goldctl"}, {"dependency": "certs"}],
            "use_cas": True,
        },
        caches = WIN_DEFAULT_CACHES,
        os = WINDOWS_OS,
    )
    common.windows_prod_builder(
        name = "Windows%s SDK Drone|frwdrn" % ("" if branch == "master" else " " + branch),
        recipe = drone_recipe_name,
        console_view_name = None,
        no_notify = True,
        caches = WIN_DEFAULT_CACHES,
        os = WINDOWS_OS,
    )

    # Windows adhoc tests
    common.windows_prod_builder(
        name = "Windows%s customer_testing|cst_test" % ("" if branch == "master" else " " + branch),
        recipe = new_recipe_name,
        console_view_name = console_view_name,
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = priority,
        properties = {
            "validation": "customer_testing",
            "validation_name": "Customer testing",
            "use_cas": True,
            "dependencies": [{"dependency": "certs"}],
        },
        caches = WIN_DEFAULT_CACHES,
        os = WINDOWS_OS,
    )

    # Mac builders
    common.builder_with_subshards(
        name = "Mac%s build_tests|bld_tests" % ("" if branch == "master" else " " + branch),
        recipe = drone_recipe_name,
        console_view_name = console_view_name,
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = priority,
        properties = {
            "shard": "build_tests",
            "subshards": ["1_4", "2_4", "3_4", "4_4"],
            "dependencies": [{"dependency": "android_sdk"}, {"dependency": "chrome_and_driver"}, {"dependency": "open_jdk"}, {"dependency": "xcode"}, {"dependency": "gems"}, {"dependency": "goldctl"}],
            "use_cas": True,
            "$flutter/osx_sdk": {
                "sdk_version": XCODE_VERSION,
            },
        },
        dimensions = {"device_type": "none"},
        caches = MAC_NEWXCODE_CACHES,
        os = MAC_OS,
        bucket = "prod",
        branch_name = "" if branch == "master" else " " + branch,
    )
    common.builder_with_subshards(
        name = "Mac%s framework_tests|frwk_tests" % ("" if branch == "master" else " " + branch),
        recipe = drone_recipe_name,
        console_view_name = console_view_name,
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = priority,
        properties = {
            "shard": "framework_tests",
            "subshards": ["libraries", "misc", "widgets"],
            "dependencies": [{"dependency": "goldctl"}],
            "$flutter/osx_sdk": {
                "sdk_version": XCODE_VERSION,
            },
            "use_cas": True,
        },
        dimensions = {"device_type": "none"},
        caches = MAC_DEFAULT_CACHES,
        os = MAC_OS,
        bucket = "prod",
        branch_name = "" if branch == "master" else " " + branch,
    )
    common.builder_with_subshards(
        name = "Mac%s tool_tests|tool_tests" % ("" if branch == "master" else " " + branch),
        recipe = drone_recipe_name,
        console_view_name = console_view_name,
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = priority,
        properties = {
            "shard": "tool_tests",
            "subshards": ["general", "commands"],
            "dependencies": [{"dependency": "android_sdk"}, {"dependency": "open_jdk"}],
            "$flutter/osx_sdk": {
                "sdk_version": XCODE_VERSION,
            },
            "use_cas": True,
        },
        dimensions = {"device_type": "none"},
        caches = MAC_DEFAULT_CACHES,
        os = MAC_OS,
        bucket = "prod",
        branch_name = "" if branch == "master" else " " + branch,
    )
    common.builder_with_subshards(
        name = "Mac%s tool_integration_tests|tool_tests_int" % ("" if branch == "master" else " " + branch),
        recipe = drone_recipe_name,
        console_view_name = console_view_name,
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = priority,
        properties = {
            "shard": "tool_integration_tests",
            "subshards": ["1_4", "2_4", "3_4", "4_4"],
            "dependencies": [{"dependency": "android_sdk"}, {"dependency": "chrome_and_driver"}, {"dependency": "open_jdk"}, {"dependency": "xcode"}, {"dependency": "gems"}, {"dependency": "goldctl"}],
            "$flutter/osx_sdk": {
                "sdk_version": XCODE_VERSION,
            },
            "use_cas": True,
        },
        dimensions = {"device_type": "none", "cores": "12"},
        caches = MAC_DEFAULT_CACHES,
        os = MAC_OS,
        bucket = "prod",
        branch_name = "" if branch == "master" else " " + branch,
    )
    common.mac_prod_builder(
        name = "Mac%s web_tool_tests|web_tt" % ("" if branch == "master" else " " + branch),
        recipe = drone_recipe_name,
        console_view_name = console_view_name,
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = priority,
        properties = {
            "shard": "web_tool_tests",
            "subshard": "web",
            "dependencies": [{"dependency": "android_sdk"}, {"dependency": "chrome_and_driver"}, {"dependency": "open_jdk"}, {"dependency": "xcode"}, {"dependency": "goldctl"}],
            "$flutter/osx_sdk": {
                "sdk_version": XCODE_VERSION,
            },
            "use_cas": True,
        },
        dimensions = {"device_type": "none"},
        caches = MAC_DEFAULT_CACHES,
        os = MAC_OS,
    )
    common.mac_prod_builder(
        name = "Mac%s SDK Drone|frwdrn" % ("" if branch == "master" else " " + branch),
        recipe = drone_recipe_name,
        console_view_name = None,
        no_notify = True,
        caches = MAC_DEFAULT_CACHES,
        dimensions = {"device_type": "none"},
        os = MAC_OS,
    )

    # Mac adhoc tests
    common.mac_prod_builder(
        name = "Mac%s customer_testing|cst_test" % ("" if branch == "master" else " " + branch),
        recipe = new_recipe_name,
        console_view_name = console_view_name,
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        priority = priority,
        properties = {
            "validation": "customer_testing",
            "validation_name": "Customer testing",
            "$flutter/osx_sdk": {
                "sdk_version": XCODE_VERSION,
            },
            "use_cas": True,
        },
        dimensions = {"device_type": "none"},
        caches = MAC_DEFAULT_CACHES,
        os = MAC_OS,
    )

def framework_try_config():
    """Try configurations for the framework repository."""

    # Defines a list view for try builders
    list_view_name = "framework-try"
    luci.list_view(
        name = "framework-try",
        title = "Framework try builders",
    )

    # Defines framework try builders

    # Linux platform

    common.builder_with_subshards(
        name = "Linux build_tests|bld_tests",
        recipe = "flutter/flutter_drone",
        repo = repos.FLUTTER,
        list_view_name = list_view_name,
        properties = {
            "shard": "build_tests",
            "subshards": ["1_2", "2_2"],
            "dependencies": [{"dependency": "android_sdk"}, {"dependency": "chrome_and_driver"}, {"dependency": "open_jdk"}, {"dependency": "goldctl"}, {"dependency": "clang"}, {"dependency": "cmake"}, {"dependency": "ninja"}, {"dependency": "curl"}],
            "use_cas": True,
        },
        caches = LINUX_DEFAULT_CACHES,
        os = LINUX_OS,
        bucket = "try",
        branch_name = None,
    )

    common.builder_with_subshards(
        name = "Linux framework_tests|frwk_tests",
        recipe = "flutter/flutter_drone",
        repo = repos.FLUTTER,
        list_view_name = list_view_name,
        properties = {
            "shard": "framework_tests",
            "subshards": ["libraries", "misc", "widgets"],
            "dependencies": [{"dependency": "goldctl"}, {"dependency": "curl"}],
            "use_cas": True,
        },
        caches = LINUX_DEFAULT_CACHES,
        os = LINUX_OS,
        bucket = "try",
        branch_name = None,
    )
    common.builder_with_subshards(
        name = "Linux tool_tests|tool_tests",
        recipe = "flutter/flutter_drone",
        repo = repos.FLUTTER,
        add_cq = True,
        list_view_name = list_view_name,
        properties = {
            "shard": "tool_tests",
            "subshards": ["general", "commands"],
            "dependencies": [{"dependency": "android_sdk"}, {"dependency": "open_jdk"}, {"dependency": "curl"}],
            "use_cas": True,
        },
        caches = LINUX_DEFAULT_CACHES,
        os = LINUX_OS,
        bucket = "try",
        branch_name = None,
    )
    common.builder_with_subshards(
        name = "Linux tool_integration_tests|tool_tests_int",
        recipe = "flutter/flutter_drone",
        repo = repos.FLUTTER,
        add_cq = True,
        list_view_name = list_view_name,
        properties = {
            "shard": "tool_integration_tests",
            "subshards": ["1_4", "2_4", "3_4", "4_4"],
            "dependencies": [{"dependency": "android_sdk"}, {"dependency": "chrome_and_driver"}, {"dependency": "open_jdk"}, {"dependency": "goldctl"}, {"dependency": "curl"}],
            "use_cas": True,
        },
        caches = LINUX_DEFAULT_CACHES,
        os = LINUX_OS,
        bucket = "try",
        branch_name = None,
    )
    common.linux_try_builder(
        name = "Linux web_tool_tests|web_tt",
        recipe = "flutter/flutter_drone",
        repo = repos.FLUTTER,
        list_view_name = list_view_name,
        properties = {
            "shard": "web_tool_tests",
            "subshard": "web",
            "dependencies": [{"dependency": "android_sdk"}, {"dependency": "chrome_and_driver"}, {"dependency": "open_jdk"}, {"dependency": "goldctl"}, {"dependency": "curl"}],
            "use_cas": True,
        },
        caches = LINUX_DEFAULT_CACHES,
        os = LINUX_OS,
    )

    common.builder_with_subshards(
        name = "Linux web_tests|web_tests",
        recipe = "flutter/flutter_drone",
        repo = repos.FLUTTER,
        list_view_name = list_view_name,
        properties = {
            "shard": "web_tests",
            "subshards": ["0", "1", "2", "3", "4", "5", "6", "7_last"],
            "dependencies": [{"dependency": "android_sdk"}, {"dependency": "chrome_and_driver"}, {"dependency": "goldctl"}, {"dependency": "curl"}],
            "use_cas": True,
        },
        caches = LINUX_DEFAULT_CACHES,
        os = LINUX_OS,
        bucket = "try",
        branch_name = None,
    )
    common.builder_with_subshards(
        name = "Linux web_long_running_tests|web_lrt",
        recipe = "flutter/flutter_drone",
        repo = repos.FLUTTER,
        list_view_name = list_view_name,
        properties = {
            "shard": "web_long_running_tests",
            "subshards": ["1_5", "2_5", "3_5", "4_5", "5_5"],
            "dependencies": [{"dependency": "android_sdk"}, {"dependency": "chrome_and_driver"}, {"dependency": "goldctl"}, {"dependency": "curl"}],
            "use_cas": True,
        },
        caches = LINUX_DEFAULT_CACHES,
        os = LINUX_OS,
        bucket = "try",
        branch_name = None,
    )
    common.linux_try_builder(
        name = "Linux SDK Drone|frwkdrn",
        recipe = "flutter/flutter_drone",
        repo = repos.FLUTTER,
        list_view_name = list_view_name,
        caches = LINUX_DEFAULT_CACHES,
        os = LINUX_OS,
    )
    common.linux_try_builder(
        name = "Linux flutter_plugins|fltplgns",
        recipe = "flutter/flutter_drone",
        repo = repos.FLUTTER,
        list_view_name = list_view_name,
        properties = {
            "shard": "flutter_plugins",
            "subshard": "analyze",
            "dependencies": [{"dependency": "curl"}],
            "use_cas": True,
        },
        caches = LINUX_DEFAULT_CACHES,
        os = LINUX_OS,
    )
    common.linux_try_builder(
        name = "Linux skp_generator|skp_gen",
        recipe = "flutter/flutter_drone",
        repo = repos.FLUTTER,
        list_view_name = list_view_name,
        properties = {
            "shard": "skp_generator",
            "subshard": "0",
            "dependencies": [{"dependency": "curl"}],
            "use_cas": True,
        },
        caches = LINUX_DEFAULT_CACHES,
        os = LINUX_OS,
    )

    # Linux platform adhoc tests
    common.linux_try_builder(
        name = "Linux analyze|anlz",
        recipe = "flutter/flutter",
        repo = repos.FLUTTER,
        list_view_name = list_view_name,
        properties = {
            "validation": "analyze",
            "validation_name": "Analyze",
            "dependencies": [{"dependency": "curl"}],
            "use_cas": True,
        },
        caches = LINUX_DEFAULT_CACHES,
        os = LINUX_OS,
    )
    common.linux_try_builder(
        name = "Linux validate_ci_config|ci_cfg",
        recipe = "flutter/flutter",
        repo = repos.FLUTTER,
        list_view_name = list_view_name,
        properties = {
            "validation": "validate_ci_config",
            "validation_name": "Validate CI config",
            "dependencies": [{"dependency": "cocoon"}],
            "use_cas": True,
        },
        caches = LINUX_DEFAULT_CACHES,
        os = LINUX_OS,
    )
    common.linux_try_builder(
        name = "Linux customer_testing|cst_tests",
        recipe = "flutter/flutter",
        repo = repos.FLUTTER,
        list_view_name = list_view_name,
        properties = {
            "validation": "customer_testing",
            "validation_name": "Customer testing",
            "dependencies": [{"dependency": "curl"}],
            "use_cas": True,
        },
        caches = LINUX_DEFAULT_CACHES,
        os = LINUX_OS,
    )
    common.linux_try_builder(
        name = "Linux docs|docs",
        recipe = "flutter/flutter",
        repo = repos.FLUTTER,
        list_view_name = list_view_name,
        properties = {
            "validation": "docs",
            "validation_name": "Docs",
            "dependencies": [{"dependency": "curl"}],
            "use_cas": True,
        },
        caches = LINUX_DEFAULT_CACHES,
        os = LINUX_OS,
    )
    common.linux_try_builder(
        name = "Linux fuchsia_precache|pcache",
        recipe = "flutter/flutter",
        repo = repos.FLUTTER,
        list_view_name = list_view_name,
        properties = {
            "validation": "fuchsia_precache",
            "validation_name": "Fuchsia precache",
            "dependencies": [{"dependency": "curl"}],
            "use_cas": True,
        },
        caches = LINUX_DEFAULT_CACHES,
        os = LINUX_OS,
    )

    # Mac platform

    common.builder_with_subshards(
        name = "Mac build_tests|bld_tests",
        recipe = "flutter/flutter_drone",
        repo = repos.FLUTTER,
        add_cq = True,
        list_view_name = list_view_name,
        properties = {
            "shard": "build_tests",
            "subshards": ["1_4", "2_4", "3_4", "4_4"],
            "dependencies": [{"dependency": "android_sdk"}, {"dependency": "chrome_and_driver"}, {"dependency": "open_jdk"}, {"dependency": "xcode"}, {"dependency": "gems"}, {"dependency": "goldctl"}],
            "$flutter/osx_sdk": {
                "sdk_version": XCODE_VERSION,
            },
            "use_cas": True,
        },
        dimensions = {"device_type": "none"},
        caches = MAC_NEWXCODE_CACHES,
        os = MAC_OS,
        bucket = "try",
        branch_name = None,
    )
    common.builder_with_subshards(
        name = "Mac framework_tests|frwk_tests",
        recipe = "flutter/flutter_drone",
        repo = repos.FLUTTER,
        list_view_name = list_view_name,
        properties = {
            "shard": "framework_tests",
            "subshards": ["libraries", "misc", "widgets"],
            "dependencies": [{"dependency": "goldctl"}],
            "$flutter/osx_sdk": {
                "sdk_version": XCODE_VERSION,
            },
            "use_cas": True,
        },
        dimensions = {"device_type": "none"},
        caches = MAC_DEFAULT_CACHES,
        os = MAC_OS,
        bucket = "try",
        branch_name = None,
    )
    common.builder_with_subshards(
        name = "Mac tool_tests|tool_tests",
        recipe = "flutter/flutter_drone",
        repo = repos.FLUTTER,
        add_cq = True,
        list_view_name = list_view_name,
        properties = {
            "shard": "tool_tests",
            "subshards": ["general", "commands"],
            "dependencies": [{"dependency": "android_sdk"}, {"dependency": "open_jdk"}],
            "$flutter/osx_sdk": {
                "sdk_version": XCODE_VERSION,
            },
            "use_cas": True,
        },
        dimensions = {"device_type": "none"},
        caches = MAC_DEFAULT_CACHES,
        os = MAC_OS,
        bucket = "try",
        branch_name = None,
    )
    common.builder_with_subshards(
        name = "Mac tool_integration_tests|tool_tests_int",
        recipe = "flutter/flutter_drone",
        repo = repos.FLUTTER,
        add_cq = True,
        list_view_name = list_view_name,
        properties = {
            "shard": "tool_integration_tests",
            "subshards": ["1_4", "2_4", "3_4", "4_4"],
            "dependencies": [{"dependency": "android_sdk"}, {"dependency": "chrome_and_driver"}, {"dependency": "open_jdk"}, {"dependency": "xcode"}, {"dependency": "gems"}, {"dependency": "goldctl"}],
            "$flutter/osx_sdk": {
                "sdk_version": XCODE_VERSION,
            },
            "use_cas": True,
        },
        dimensions = {"device_type": "none"},
        caches = MAC_DEFAULT_CACHES,
        os = MAC_OS,
        bucket = "try",
        branch_name = None,
    )
    common.mac_try_builder(
        name = "Mac web_tool_tests|web_tt",
        recipe = "flutter/flutter_drone",
        repo = repos.FLUTTER,
        list_view_name = list_view_name,
        properties = {
            "shard": "web_tool_tests",
            "subshard": "web",
            "dependencies": [{"dependency": "android_sdk"}, {"dependency": "chrome_and_driver"}, {"dependency": "open_jdk"}, {"dependency": "xcode"}, {"dependency": "goldctl"}],
            "$flutter/osx_sdk": {
                "sdk_version": XCODE_VERSION,
            },
            "use_cas": True,
        },
        dimensions = {"device_type": "none"},
        caches = MAC_DEFAULT_CACHES,
        os = MAC_OS,
    )
    common.mac_try_builder(
        name = "Mac SDK Drone|frwkdrn",
        recipe = "flutter/flutter_drone",
        repo = repos.FLUTTER,
        list_view_name = list_view_name,
        caches = MAC_DEFAULT_CACHES,
        dimensions = {"device_type": "none"},
        os = MAC_OS,
    )

    # Mac adhoc test
    common.mac_try_builder(
        name = "Mac customer_testing|cst_test",
        recipe = "flutter/flutter",
        repo = repos.FLUTTER,
        add_cq = True,
        list_view_name = list_view_name,
        properties = {
            "validation": "customer_testing",
            "validation_name": "Customer testing",
            "$flutter/osx_sdk": {
                "sdk_version": XCODE_VERSION,
            },
            "use_cas": True,
        },
        dimensions = {"device_type": "none"},
        caches = MAC_DEFAULT_CACHES,
        os = MAC_OS,
    )

    # Windows platform
    common.builder_with_subshards(
        name = "Windows build_tests|bld_tests",
        recipe = "flutter/flutter_drone",
        repo = repos.FLUTTER,
        list_view_name = list_view_name,
        properties = {
            "shard": "build_tests",
            "subshards": ["1_3", "2_3", "3_3"],
            "dependencies": [{"dependency": "android_sdk"}, {"dependency": "chrome_and_driver"}, {"dependency": "open_jdk"}, {"dependency": "goldctl"}, {"dependency": "certs"}, {"dependency": "vs_build"}],
            "use_cas": True,
        },
        caches = WIN_DEFAULT_CACHES,
        os = WINDOWS_OS,
        bucket = "try",
        branch_name = None,
    )
    common.builder_with_subshards(
        name = "Windows framework_tests|frwk_tests",
        recipe = "flutter/flutter_drone",
        repo = repos.FLUTTER,
        list_view_name = list_view_name,
        properties = {
            "shard": "framework_tests",
            "subshards": ["libraries", "misc", "widgets"],
            "dependencies": [{"dependency": "goldctl"}, {"dependency": "certs"}],
            "use_cas": True,
        },
        caches = WIN_DEFAULT_CACHES,
        os = WINDOWS_OS,
        bucket = "try",
        branch_name = None,
    )
    common.builder_with_subshards(
        name = "Windows tool_tests|tool_tests",
        recipe = "flutter/flutter_drone",
        repo = repos.FLUTTER,
        add_cq = True,
        list_view_name = list_view_name,
        properties = {
            "shard": "tool_tests",
            "subshards": ["general", "commands"],
            "dependencies": [{"dependency": "android_sdk"}, {"dependency": "open_jdk"}, {"dependency": "certs"}],
            "use_cas": True,
        },
        caches = WIN_DEFAULT_CACHES,
        os = WINDOWS_OS,
        bucket = "try",
        branch_name = None,
    )
    common.builder_with_subshards(
        name = "Windows tool_integration_tests|tool_tests_int",
        recipe = "flutter/flutter_drone",
        repo = repos.FLUTTER,
        add_cq = True,
        list_view_name = list_view_name,
        properties = {
            "shard": "tool_integration_tests",
            "subshards": ["1_5", "2_5", "3_5", "4_5", "5_5"],
            "dependencies": [{"dependency": "android_sdk"}, {"dependency": "chrome_and_driver"}, {"dependency": "open_jdk"}, {"dependency": "goldctl"}, {"dependency": "certs"}, {"dependency": "vs_build"}],
            "use_cas": True,
        },
        caches = WIN_DEFAULT_CACHES,
        os = WINDOWS_OS,
        bucket = "try",
        branch_name = None,
    )
    common.windows_try_builder(
        name = "Windows web_tool_tests|web_tt",
        recipe = "flutter/flutter_drone",
        repo = repos.FLUTTER,
        list_view_name = list_view_name,
        properties = {
            "shard": "web_tool_tests",
            "subshard": "web",
            "dependencies": [{"dependency": "android_sdk"}, {"dependency": "chrome_and_driver"}, {"dependency": "open_jdk"}, {"dependency": "goldctl"}, {"dependency": "certs"}],
            "use_cas": True,
        },
        caches = WIN_DEFAULT_CACHES,
        os = WINDOWS_OS,
    )
    common.windows_try_builder(
        name = "Windows SDK Drone|frwkdrn",
        recipe = "flutter/flutter_drone",
        repo = repos.FLUTTER,
        list_view_name = list_view_name,
        caches = WIN_DEFAULT_CACHES,
        os = WINDOWS_OS,
    )

    # Windows adhoc tests
    common.windows_try_builder(
        name = "Windows customer_testing|cst_tests",
        recipe = "flutter/flutter",
        repo = repos.FLUTTER,
        add_cq = True,
        list_view_name = list_view_name,
        properties = {
            "validation": "customer_testing",
            "validation_name": "Customer testing",
            "use_cas": True,
            "dependencies": [{"dependency": "certs"}],
        },
        caches = WIN_DEFAULT_CACHES,
        os = WINDOWS_OS,
    )

framework_config = struct(setup = _setup)
