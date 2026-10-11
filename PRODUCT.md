# 轻贴 Lan Clip

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Stack

用户指定 Flutter，支持 Android、Windows、macOS；不引入 Rust。

## Users

同时使用安卓手机、Windows 电脑和 Mac 的个人用户。

## Product Purpose

手机主动发送文字或单张图片，所有已配对且在线的电脑自动写入系统剪贴板，用户直接粘贴。

## Operating Context

设备处于同一个 Wi-Fi。用户接受打开小 App 后点击发送。电脑端后台接收。

## Capabilities and Constraints

首次配对；后续自动发现并同时发送给两台电脑。文字发送打开空白输入框，由用户输入或手动粘贴，不自动读取剪贴板；图片通过系统选图后发送。单向发送。暂不包含云同步、文件夹、历史剪贴板归档。

## Brand Commitments

中文、简洁浅色界面，手机两个同等大小的紧凑发送按钮；设备用状态灯和在线/离线标签。不放重复的 Wi-Fi、群发或后台接收说明。用户已确认。轻贴是暂定项目名称。

## Product Principles

- 日常操作不选择目标电脑。
- 只有接收端完成剪贴板写入才显示发送成功。
- 独立报告每台电脑的结果，离线设备不阻塞在线设备。
- 接收窗口关闭后仍可后台接收，并能明确退出。

## Evidence on Hand

功能要求来自本聊天。项目为全新代码；本机尚无 Android SDK 和完整 Xcode，原生构建与真机验证范围必须如实记录。
