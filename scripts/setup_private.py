#!/usr/bin/env python3
"""Collect OKX credentials privately on the local terminal; never read them back."""

import getpass
import json
import os
from pathlib import Path
import secrets
import stat
import sys
import warnings


PROFILE = "codex-readonly"
CONFIG_NAME = "config.toml"
MARKER_NAME = "codex-readonly-ready"
SITES = ("global", "eea", "us", "tr")


class SetupFailure(Exception):
    """Only fixed, non-sensitive messages may be supplied to this exception."""


def exists_at(directory_fd, name):
    try:
        os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
    except FileNotFoundError:
        return False
    return True


def open_private_directory():
    directory = Path.home() / ".okx"
    try:
        os.mkdir(directory, mode=0o700)
    except FileExistsError:
        pass

    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    directory_fd = os.open(directory, flags)
    try:
        info = os.fstat(directory_fd)
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
            raise SetupFailure("停止：~/.okx 不是当前用户拥有的普通目录。")
        os.fchmod(directory_fd, 0o700)
    except BaseException:
        os.close(directory_fd)
        raise
    return directory_fd


def read_secret(label):
    while True:
        with warnings.catch_warnings():
            # getpass must stop instead of ever falling back to echoed input.
            warnings.simplefilter("error", getpass.GetPassWarning)
            value = getpass.getpass(label)
        if value and not value.isspace() and all(0x20 <= ord(c) <= 0x7E for c in value):
            return value
        print("输入无效：请使用非空、单行的可打印英文字符；内容不会显示。", file=sys.stderr)


def publish_private_file(directory_fd, name, contents):
    """Publish a complete 0600 file atomically without replacing any existing path."""
    temporary_name = ".codex-private-" + secrets.token_hex(16)
    temporary_created = False
    try:
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
        fd = os.open(temporary_name, flags, 0o600, dir_fd=directory_fd)
        temporary_created = True
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            os.fchmod(handle.fileno(), 0o600)
            handle.write(contents)
            handle.flush()
            os.fsync(handle.fileno())
        # A hard link publishes the already-complete file and fails if name exists.
        os.link(
            temporary_name,
            name,
            src_dir_fd=directory_fd,
            dst_dir_fd=directory_fd,
            follow_symlinks=False,
        )
        os.fsync(directory_fd)
    finally:
        if temporary_created:
            os.unlink(temporary_name, dir_fd=directory_fd)


def main():
    directory_fd = None
    config_published = False
    try:
        if not sys.stdin.isatty() or not sys.stderr.isatty():
            raise SetupFailure("停止：请在本机 Terminal 的交互终端运行，不能通过管道输入凭据。")

        directory_fd = open_private_directory()
        if exists_at(directory_fd, CONFIG_NAME):
            raise SetupFailure("停止：~/.okx/config.toml 已存在；未读取、未覆盖。请让配置助手处理已有配置。")
        if exists_at(directory_fd, MARKER_NAME):
            raise SetupFailure("停止：已有就绪标记；未读取任何文件。请让配置助手检查现有状态。")

        print("仅使用您刚创建的 Read 权限 API；不要启用 Trade 或 Withdraw。")
        print("以下三个输入均隐藏，内容只保存到本机 ~/.okx/config.toml。")
        while True:
            site = input("账户站点 global / eea / us / tr [global]：").strip().lower() or "global"
            if site in SITES:
                break
            print("请选择 global、eea、us 或 tr。", file=sys.stderr)

        api_key = read_secret("API Key（隐藏输入）：")
        secret_key = read_secret("Secret Key（隐藏输入）：")
        passphrase = read_secret("Passphrase（隐藏输入）：")

        # Printable ASCII plus JSON string escaping is valid for TOML basic strings.
        config = (
            f'default_profile = "{PROFILE}"\n\n'
            f'[profiles.{PROFILE}]\n'
            f"api_key = {json.dumps(api_key)}\n"
            f"secret_key = {json.dumps(secret_key)}\n"
            f"passphrase = {json.dumps(passphrase)}\n"
            "demo = false\n"
            f"site = {json.dumps(site)}\n"
        )
        try:
            publish_private_file(directory_fd, CONFIG_NAME, config)
        except FileExistsError:
            raise SetupFailure("停止：配置路径已由其他程序创建；未读取、未覆盖。请让配置助手处理。") from None
        config_published = True
        publish_private_file(directory_fd, MARKER_NAME, "codex-readonly private setup complete\n")
        print("私密配置已保存，权限为 0600；就绪标记已创建。请返回对话继续只读验收。")
        return 0
    except KeyboardInterrupt:
        print("\n已取消；未显示任何凭据。", file=sys.stderr)
        return 130
    except SetupFailure as error:
        print(str(error), file=sys.stderr)
        return 1
    except Exception:
        if config_published:
            message = "配置已安全保存，但就绪标记未完成；请让配置助手检查状态，不要重复输入。"
        else:
            message = "配置未能完成；未显示错误详情以保护凭据。请让配置助手检查文件状态后再继续。"
        print(message, file=sys.stderr)
        return 1
    finally:
        if directory_fd is not None:
            os.close(directory_fd)


if __name__ == "__main__":
    sys.exit(main())
