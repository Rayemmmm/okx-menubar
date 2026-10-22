// Documentation illustration only. All values are fictional; no account or network access.
import AppKit

let width=1280, height=1160
let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,
    bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
func rect(_ x:CGFloat,_ top:CGFloat,_ w:CGFloat,_ h:CGFloat,_ color:NSColor,_ radius:CGFloat=0) {
    color.setFill();NSBezierPath(roundedRect:NSRect(x:x,y:CGFloat(height)-top-h,width:w,height:h),xRadius:radius,yRadius:radius).fill()
}
func text(_ s:String,_ x:CGFloat,_ top:CGFloat,_ size:CGFloat=25,_ color:NSColor = .black,_ weight:NSFont.Weight = .regular) {
    (s as NSString).draw(at:NSPoint(x:x,y:CGFloat(height)-top-size*1.25),withAttributes:[
        .font:NSFont.systemFont(ofSize:size,weight:weight),.foregroundColor:color])
}
let ink=NSColor(calibratedRed:0.12,green:0.16,blue:0.20,alpha:1)
let gray=NSColor(calibratedWhite:0.42,alpha:1)
let green=NSColor(calibratedRed:0.05,green:0.48,blue:0.29,alpha:1)
rect(0,0,1280,1160,NSColor(calibratedRed:0.91,green:0.94,blue:0.98,alpha:1))
text("OKX ReadOnly · macOS",64,30,36,ink,.bold)
text("界面示意 · 全部虚构数据 · 非实时行情",64,80,22,gray)
rect(64,140,1152,66,NSColor(calibratedWhite:0.98,alpha:1),14)
text("Finder",88,158,23,ink,.semibold)
rect(300,150,886,46,NSColor(calibratedRed:0.88,green:0.96,blue:0.92,alpha:1),8)
text("OKX 总1000.00U · 浮+2.50U · BTC80000.0",322,159,27,green,.semibold)
rect(432,225,770,865,NSColor(calibratedWhite:0,alpha:0.08),18)
rect(424,217,770,865,NSColor(calibratedWhite:0.99,alpha:1),18)
let left:CGFloat=452
func row(_ s:String,_ y:CGFloat,_ bold:Bool=false,_ color:NSColor=ink) {text(s,left,y,24,color,bold ? .semibold : .regular)}
func separator(_ y:CGFloat) {rect(left,y,714,1,NSColor(calibratedWhite:0.87,alpha:1))}
row("OKX · 只读账户显示",238,true)
row("演示数据 · 未连接账户",278,false,gray)
separator(323)
row("BTC 浮动盈亏    +2.5000 USDT",340,true,green)
row("总余额（折合 USDT）    1000.0000 USDT",384,true)
row("USDT 现金余额（不含浮盈亏）    997.5000",428)
row("USDT 交易权益（含浮盈亏）    1000.0000",472)
row("可用余额    986.6667 USDT",516)
separator(565)
row("空单  0.05 张 · 0.000500 BTC",583,true)
row("3 倍 · 逐仓 · 开仓均价 85000.00",627)
row("最新成交价 80000.00 · 标记价 80000.00",671)
separator(720)
row("止盈 78000.00 · 最新价触发 · 触发后市价",738)
row("止损 84000.00 · 最新价触发 · 触发后市价",782)
row("普通挂单 0 笔",826)
separator(875)
row("显示内容                                      ›",893)
row("刷新频率（当前 5 秒）                   ›",937)
row("暂停刷新",981)
row("退出 OKX ReadOnly",1025)
text("文档示意图，不是实际账户截图；界面以当前版本为准。",64,1111,21,gray)
let out=CommandLine.arguments[1]
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:out))
