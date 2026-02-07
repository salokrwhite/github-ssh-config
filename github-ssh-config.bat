@echo off
chcp 65001 >nul
title GitHub SSH 配置工具
cls

cd /d "%~dp0"

echo ==========================================
echo    GitHub SSH 一键配置工具
echo ==========================================
echo.
echo  [重要告示]
echo  1. 如需启动 ssh-agent 服务，请右键选择"以管理员身份运行"此脚本

echo  2. 完整配置：适用于首次配置或更换电脑的仓库

echo  3. 简易配置：适用于已配置过 SSH，仅切换新仓库的远程地址

echo  4. 全局 SSH 克隆：全局配置 git clone 自动使用 SSH

echo  5. 恢复 HTTPS 克隆：恢复 git clone 使用 HTTPS 协议

echo.
echo ==========================================
echo.

if not exist ".git" (
    echo 当前目录不是 Git 项目
    echo 请把此脚本放到你的项目文件夹里运行。
    pause
    exit /b 1
)

echo 请选择配置模式：

echo   [1] 完整配置 - 生成密钥、配置 SSH、设置仓库（首次使用选这个）

echo   [2] 简易配置 - 仅测试连接并切换远程地址（已配置过 SSH 选这个）

echo   [3] 全局 SSH 克隆 - 配置 git clone 自动使用 SSH 代替 HTTPS

echo   [4] 恢复 HTTPS 克隆 - 恢复 git clone 使用 HTTPS 协议
echo.
set /p MODE="请输入选项 (1/2/3/4)："
echo.

if "%MODE%"=="4" goto RESTORE_HTTPS_MODE
if "%MODE%"=="3" goto GLOBAL_SSH_MODE
if "%MODE%"=="2" goto SIMPLE_MODE
if "%MODE%"=="1" goto FULL_MODE

echo 未选择或输入错误，使用默认完整配置模式...
echo.
goto FULL_MODE

:FULL_MODE
echo 【完整配置模式】
echo.

set /p EMAIL="请输入你的 GitHub 注册邮箱："
if "%EMAIL%"=="" (
    echo [错误] 邮箱不能为空！
    pause
    exit /b 1
)
echo 邮箱已设为：%EMAIL%
echo.

set "KEY_PATH=%USERPROFILE%\.ssh\id_ed25519"
set "PUB_PATH=%USERPROFILE%\.ssh\id_ed25519.pub"

if exist "%KEY_PATH%" (
    echo [步骤 1] 检测到已有密钥，跳过生成。
) else (
    echo [步骤 1] 正在生成 SSH 密钥...
    ssh-keygen -t ed25519 -C "%EMAIL%" -f "%KEY_PATH%" -N ""
    if errorlevel 1 (
        echo [错误] 密钥生成失败！
        pause
        exit /b 1
    )
    echo 密钥已生成！
)

echo.
echo [步骤 2] 复制公钥到剪贴板...
type "%PUB_PATH%" | clip
echo 公钥已复制到剪贴板！
echo.
echo 请立即打开浏览器，访问：
echo    https://github.com/settings/keys
echo.
echo 操作步骤：
echo    1. 点击 SSH and GPG keys
echo    2. 然后点击 New SSH key
echo    3. Key 处粘贴，Title 随意，Key type 选择 Authentication Key
echo    4. 点击 Add SSH key
echo.
pause

echo.
echo [步骤 3] 启动 SSH Agent...
echo.
echo 说明：ssh-agent 是 Windows 系统服务，不会创建 agent 文件夹

echo.
echo [3.1] 检查 ssh-agent 服务状态...
sc query ssh-agent | findstr "STATE"

echo.
echo [3.2] 设置 ssh-agent 服务为自动启动...
sc config ssh-agent start= auto
if errorlevel 1 (
    echo [警告] 设置自动启动失败，可能需要管理员权限
) else (
    echo 自动启动设置成功
)

echo.
echo [3.3] 启动 ssh-agent 服务...
net start ssh-agent
if errorlevel 1 (
    REM 检查是否真的失败了，还是只是已在运行
    sc query ssh-agent | findstr /i "RUNNING" >nul
    if errorlevel 1 (
        echo [警告] 服务未能启动，可能需要管理员权限
    ) else (
        echo 服务已在运行，无需重新启动
    )
) else (
    echo 服务启动成功
)

echo.
echo [3.4] 添加密钥到 ssh-agent...
echo 密钥路径: %KEY_PATH%
ssh-add "%KEY_PATH%"
if errorlevel 1 (
    echo.
    echo [错误] 添加密钥失败！可能原因：
    echo   1. ssh-agent 服务未运行
    echo   2. 密钥文件路径错误
    echo   3. 没有管理员权限
    echo.
    echo 尝试手动运行以下命令诊断：
    echo   ssh-agent -s
    echo   ssh-add "%KEY_PATH%"
)

goto TEST_AND_SET_REMOTE

:SIMPLE_MODE
echo 【简易配置模式 - 跳过密钥生成，直接测试连接并切换远程地址】
echo.

:TEST_AND_SET_REMOTE

echo.
echo [步骤 4] 测试 GitHub 连接...
echo 如果看到 "Hi xxx! You've successfully authenticated" 说明成功！
echo.
ssh -o StrictHostKeyChecking=no -T git@github.com 2>&1 | findstr /i "successfully authenticated" >nul
if errorlevel 1 (
    echo.
    echo [错误] SSH 连接测试失败！
    echo 可能原因：
    echo   1. 公钥未添加到 GitHub（最常见）
    echo   2. 网络问题
    echo   3. SSH 密钥配置错误
    echo.
    echo 请检查：
    echo   - 是否已将公钥添加到 https://github.com/settings/keys
    echo   - 如果刚添加，请等待 1-2 分钟再试
    echo.
    echo 配置已中止，请解决问题后重新运行脚本。
    pause
    exit /b 1
)
echo [成功] SSH 连接测试通过！
echo.

echo [步骤 5] 设置远程仓库为 SSH...
git remote get-url origin >nul 2>&1
if errorlevel 1 (
    echo 未找到远程地址，跳过设置
) else (
    for /f "tokens=*" %%a in ('git remote get-url origin') do (
        set "REMOTE=%%a"
        echo 当前远程地址：%%a
    )
    set "REMOTE=%REMOTE:https://github.com/=git@github.com:%"
    set "REMOTE=%REMOTE:http://github.com/=git@github.com:%"
    set "REMOTE=%REMOTE:.git=%"
    
    git remote set-url origin "%REMOTE%.git"
    echo 已改为 SSH 模式：%REMOTE%.git
)

:GLOBAL_SSH_MODE
echo 【全局 SSH 克隆配置模式】
echo.
echo 此模式将配置 Git 全局设置，使 git clone 自动使用 SSH 协议。

echo 配置后，即使用 git clone https://github.com/user/repo.git 也会自动使用 SSH。
echo.

echo [步骤 1] 配置 Git 全局替换规则...
echo 配置 HTTPS 替换...
git config --global url."git@github.com:".insteadOf "https://github.com/"
if errorlevel 1 (
    echo [警告] HTTPS 配置可能失败，继续尝试 HTTP...
)
echo 配置 HTTP 替换...
git config --global --add url."git@github.com:".insteadOf "http://github.com/"
if errorlevel 1 (
    echo [警告] HTTP 配置可能失败，继续验证...
)
echo.
echo 全局配置完成！
echo.

echo [步骤 2] 验证配置...
echo 当前 Git 全局 URL 替换规则：
git config --global --get-all url."git@github.com:".insteadOf
if errorlevel 1 (
    echo （无配置，配置可能失败）
)
echo.

echo 配置完成！现在你可以直接使用：

echo git clone https://github.com/用户名/仓库名.git

echo Git 会自动转换为 SSH 协议进行克隆。
echo.
pause
exit /b 0

:RESTORE_HTTPS_MODE
echo 【恢复 HTTPS 克隆配置模式】
echo.
echo 此模式将删除 Git 全局 SSH 替换配置，恢复 git clone 使用 HTTPS 协议。
echo.

echo [步骤 1] 删除 Git 全局 SSH 替换规则...
echo 正在删除 https 配置...
git config --global --unset url."git@github.com:".insteadOf "https://github.com/" 2>nul
echo 正在删除 http 配置...
git config --global --unset url."git@github.com:".insteadOf "http://github.com/" 2>nul
echo 配置删除完成！
echo.

echo [步骤 2] 验证当前配置...
echo 当前 Git 全局 URL 替换规则：
git config --global --get-all url."git@github.com:".insteadOf
if errorlevel 1 (
    echo （无配置，当前使用默认 HTTPS 协议）
)
echo.

echo 配置完成！现在 git clone 将使用原始协议（HTTPS）。
echo.
pause
exit /b 0

echo.
echo ==========================================
if "%MODE%"=="2" (
    echo    简易配置完成！
) else if "%MODE%"=="3" (
    echo    全局 SSH 克隆配置完成！
) else if "%MODE%"=="4" (
    echo    HTTPS 恢复配置完成！
) else (
    echo    完整配置完成！
)
echo ==========================================
echo.
echo 你现在可以：
echo    - 在终端输入：git push origin main
echo    - 在 VS Code 中直接点 Push
echo    - 永久告别 HTTPS 连接超时
echo.
pause
