这是一个自动化的Linux系统监控脚本，可以检查：
- 磁盘使用情况
- 内存使用情况  
- 系统负载
- 服务状态

自动生成HTML报告，支持邮件通知。
基本使用（无需邮件配置）：
```bash
# 克隆项目
git clone https://github.com/feiyu978/linux-system-monitor.git
cd linux-system-monitor
# 运行监控脚本
chmod +x bin/system_check.sh
./bin/system_check.sh
# 查看生成的报告
ls -la templates/
查看报告：
脚本会在 templates/ 目录生成HTML格式的监控报告，直接在浏览器中打开即可查看。
最终运行结果为：
![Uploading 图片1.png…]()
