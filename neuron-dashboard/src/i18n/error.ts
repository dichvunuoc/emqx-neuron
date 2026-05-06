/**
 * When updating here, the @/utils/constants.ts file ERROR_CODE_ARR should be updated together.
 */
export default {
  1000: {
    zh: '通用错误',
    en: 'Generic error',
    vi: 'Lỗi chung',
  },
  1001: {
    zh: '内部错误',
    en: 'Internal error',
    vi: 'Lỗi nội bộ',
  },
  1002: {
    zh: '请求 body 无效',
    en: 'Request body invalid',
    vi: 'Nội dung body yêu cầu không hợp lệ',
  },
  1003: {
    zh: '请求 param 无效',
    en: 'Request param invalid',
    vi: 'Tham số yêu cầu không hợp lệ',
  },
  1004: {
    zh: '缺少令牌',
    en: 'Missing token',
    vi: 'Thiếu token',
  },
  1005: {
    zh: '解码令牌错误',
    en: 'Decoding token error',
    vi: 'Lỗi giải mã token',
  },
  1006: {
    zh: '令牌过期',
    en: 'Expired token',
    vi: 'Token đã hết hạn',
  },
  1007: {
    zh: '验证令牌错误',
    en: 'Validate token error',
    vi: 'Lỗi xác thực token',
  },
  1008: {
    zh: '无效令牌',
    en: 'Invalid token',
    vi: 'Token không hợp lệ',
  },
  1009: {
    zh: '用户名或密码错误',
    en: 'User or password error',
    vi: 'Tên đăng nhập hoặc mật khẩu sai',
  },
  1010: {
    zh: '程序繁忙',
    en: 'Is busy',
    vi: 'Hệ thống đang bận',
  },
  1011: {
    zh: '文件不存在',
    en: 'File not exist',
    vi: 'Tệp không tồn tại',
  },
  1012: {
    zh: '密码长度太短或太长',
    en: 'Password length too short or too long',
    vi: 'Độ dài mật khẩu quá ngắn hoặc quá dài',
  },
  1013: {
    zh: '密码重复',
    en: 'Duplicate password',
    vi: 'Mật khẩu trùng lặp',
  },
  1014: {
    zh: '执行指令失败',
    en: 'Command execution failed',
    vi: 'Thực thi lệnh thất bại',
  },
  1015: {
    zh: 'IP 地址无效',
    en: 'Invalid ip address',
    vi: 'Địa chỉ IP không hợp lệ',
  },
  1016: {
    zh: 'IP 地址已占用',
    en: 'IP address in use',
    vi: 'Địa chỉ IP đang được sử dụng',
  },
  1017: {
    zh: '用户名无效',
    en: 'Invalid user',
    vi: 'Người dùng không hợp lệ',
  },
  1018: {
    zh: '密码无效',
    en: 'Invalid password',
    vi: 'Mật khẩu không hợp lệ',
  },

  2002: {
    zh: 'Node 已存在',
    en: 'Node exist',
    vi: 'Node đã tồn tại',
  },
  2003: {
    zh: 'Node 不存在',
    en: 'Node not exist',
    vi: 'Node không tồn tại',
  },
  2004: {
    zh: 'Node 设置无效',
    en: 'Node setting invalid',
    vi: 'Cấu hình node không hợp lệ',
  },
  2005: {
    zh: 'Node 设置未找到',
    en: 'Node setting not found',
    vi: 'Không tìm thấy cấu hình node',
  },
  2006: {
    zh: 'Node 未准备好',
    en: 'Node not ready',
    vi: 'Node chưa sẵn sàng',
  },
  2007: {
    zh: 'Node 正在运行',
    en: 'Node is running',
    vi: 'Node đang chạy',
  },
  2008: {
    zh: 'Node 未运行',
    en: 'Node not running',
    vi: 'Node không chạy',
  },
  2009: {
    zh: 'Node 已停止',
    en: 'Node is stopped',
    vi: 'Node đã dừng',
  },
  2010: {
    zh: 'Node 名称过长',
    en: 'Node name too long',
    vi: 'Tên node quá dài',
  },
  2011: {
    zh: 'Node 不允许删除',
    en: 'Node not allow delete',
    vi: 'Node không được phép xóa',
  },
  2012: {
    zh: 'Node 不允许订阅',
    en: 'Node not allow subscribe',
    vi: 'Node không được phép đăng ký theo dõi',
  },
  2013: {
    zh: 'Node 不允许更新',
    en: 'Node not allow update',
    vi: 'Node không được phép cập nhật',
  },
  2014: {
    zh: 'Node 不支持图',
    en: 'Node not allow map',
    vi: 'Node không được phép ánh xạ (map)',
  },
  2015: {
    zh: 'Node 名称不允许为空',
    en: 'Node name is empty',
    vi: 'Tên node không được để trống',
  },
  2101: {
    zh: '组已经被订阅',
    en: 'Group already subscribed',
    vi: 'Nhóm đã được đăng ký theo dõi',
  },
  2102: {
    zh: '组未被订阅',
    en: 'Group not subscribe',
    vi: 'Nhóm chưa được đăng ký theo dõi',
  },
  2103: {
    zh: '组不允许',
    en: 'Group not allow',
    vi: 'Nhóm không được phép',
  },
  2104: {
    zh: '组已存在',
    en: 'Group exist',
    vi: 'Nhóm đã tồn tại',
  },
  2105: {
    zh: '组参数无效',
    en: 'Group parameter invalid',
    vi: 'Tham số nhóm không hợp lệ',
  },
  2106: {
    zh: '组不存在',
    en: 'Group not exist',
    vi: 'Nhóm không tồn tại',
  },
  2107: {
    zh: '组名称过长',
    en: 'Group name too long',
    vi: 'Tên nhóm quá dài',
  },
  2201: {
    zh: '点位不存在',
    en: 'Tag not exist',
    vi: 'Tag không tồn tại',
  },
  2202: {
    zh: '点位名称冲突',
    en: 'Tag name conflict',
    vi: 'Xung đột tên tag',
  },
  2203: {
    zh: '点位属性不支持',
    en: 'Tag attribute not support',
    vi: 'Thuộc tính tag không được hỗ trợ',
  },
  2204: {
    zh: '点位类型不支持',
    en: 'Tag type not support',
    vi: 'Kiểu tag không được hỗ trợ',
  },
  2205: {
    zh: '点位地址格式无效',
    en: 'Tag address format invalid',
    vi: 'Định dạng địa chỉ tag không hợp lệ',
  },
  2206: {
    zh: '点位名称过长',
    en: 'Tag name too long',
    vi: 'Tên tag quá dài',
  },
  2207: {
    zh: '点位地址过长',
    en: 'Tag address too long',
    vi: 'Địa chỉ tag quá dài',
  },
  2208: {
    zh: '点位描述过长',
    en: 'Tag description too long',
    vi: 'Mô tả tag quá dài',
  },
  2209: {
    zh: '点位精度无效',
    en: 'Tag precision invalid',
    vi: 'Độ chính xác tag không hợp lệ',
  },
  2210: {
    zh: '点位已存在',
    en: 'Tag exist',
    vi: 'Tag đã tồn tại',
  },
  2301: {
    zh: '库未找到',
    en: 'Library not found',
    vi: 'Không tìm thấy thư viện',
  },
  2302: {
    zh: '库信息无效',
    en: 'Library info invalid',
    vi: 'Thông tin thư viện không hợp lệ',
  },
  2303: {
    zh: '库名称冲突',
    en: 'Library name conflict',
    vi: 'Xung đột tên thư viện',
  },
  2304: {
    zh: '库打开失败',
    en: 'Library failed to open',
    vi: 'Mở thư viện thất bại',
  },
  2305: {
    zh: '库模块无效',
    en: 'Libraray module invalid',
    vi: 'Module thư viện không hợp lệ',
  },
  2306: {
    zh: '系统库不允许删除',
    en: 'Library system not allow del',
    vi: 'Không được phép xóa thư viện hệ thống',
  },
  2307: {
    zh: '插件不允许实例化',
    en: 'Library not allow create instance',
    vi: 'Plugin không được phép tạo phiên bản',
  },
  2308: {
    zh: '插件不支持此架构',
    en: 'Library arch not support',
    vi: 'Kiến trúc không được plugin hỗ trợ',
  },
  2400: {
    zh: 'License 未找到',
    en: 'License not found',
    vi: 'Không tìm thấy License',
  },
  2401: {
    zh: 'License 无效',
    en: 'License invalid',
    vi: 'License không hợp lệ',
  },
  2402: {
    zh: 'License 过期',
    en: 'License expired',
    vi: 'License đã hết hạn',
  },
  uploadLicense2402: {
    zh: `您的 License 已过期，
    请<a target="_blank" rel="noopener norefferrer" href="https://www.emqx.com/zh/apply-licenses/neuron">更新 License</a>
    或联系销售人员更新 License。`,
    en: `Your License has expired,
    please <a target="_blank" rel="noopener norefferrer" href="https://www.emqx.com/zh/apply-licenses/neuron">update the License</a>
    or contact the sales staff to update the License.`,
    vi: `License của bạn đã hết hạn,
    vui lòng <a target="_blank" rel="noopener norefferrer" href="https://www.emqx.com/zh/apply-licenses/neuron">cập nhật License</a>
    hoặc liên hệ bộ phận kinh doanh để cập nhật License.`,
  },
  2403: {
    zh: 'License 未启用插件',
    en: 'Plugin disabled by license',
    vi: 'Plugin bị vô hiệu hóa bởi License',
  },
  uploadLicense2403: {
    zh: `导入 License 失败，请先删除 License 不包含的驱动`,
    en: `Failed to import the License, please delete the driver not included in the License.`,
    vi: `Nhập License thất bại, vui lòng xóa trình điều khiển không nằm trong License trước.`,
  },
  2404: {
    zh: '达到 license 授权的最大节点数',
    en: 'Reach licensed max number of nodes',
    vi: 'Đạt số node tối đa theo License',
  },
  uploadLicense2404: {
    zh: `节点数超过 License 限制，Neuron 无法正常使用，
    请<a target="_blank" rel="noopener norefferrer" href="https://www.emqx.com/zh/apply-licenses/neuron">更新 License</a>
    或删除部分驱动节点。`,
    en: `The count of nodes exceeds the license limit, and Neuron cannot be used normally.
    Please <a target="_blank" rel="noopener norefferrer" href="https://www.emqx.com/zh/apply-licenses/neuron">update the license</a>
    or delete some driver nodes.`,
    vi: `Số node vượt quá giới hạn License, Neuron không thể hoạt động bình thường.
    Vui lòng <a target="_blank" rel="noopener norefferrer" href="https://www.emqx.com/zh/apply-licenses/neuron">cập nhật License</a>
    hoặc xóa bớt một số node trình điều khiển.`,
  },
  addDriverByPlugin2404: {
    zh: '节点数超过 License 限制，创建驱动失败',
    en: 'The count of nodes exceeds the limit of the license, and the creation of the driver fails',
    vi: 'Số node vượt quá giới hạn License, tạo trình điều khiển thất bại',
  },
  addDriverByTemplate2404: {
    zh: '节点数超过 License 限制，创建驱动失败',
    en: 'The count of nodes exceeds the limit of the license, and the creation of the driver fails',
    vi: 'Số node vượt quá giới hạn License, tạo trình điều khiển thất bại',
  },
  2405: {
    zh: '达到 license 授权的节点最大点位数',
    en: 'Reach licensed max number of tags per node',
    vi: 'Đạt số tag tối đa trên mỗi node theo License',
  },
  uploadLicense2405: {
    zh: `点位数超过 License 限制，Neuron 无法正常使用，
    请<a target="_blank" rel="noopener norefferrer" href="https://www.emqx.com/zh/apply-licenses/neuron">更新 License</a>
    或删除部分点位。`,
    en: `The count of data tags exceeds the license limit, and Neuron cannot be used normally.
    Please <a target="_blank" rel="noopener norefferrer" href="https://www.emqx.com/zh/apply-licenses/neuron">update the license</a>
    or delete some data tags.`,
    vi: `Số lượng tag dữ liệu vượt quá giới hạn License, Neuron không thể hoạt động bình thường.
    Vui lòng <a target="_blank" rel="noopener norefferrer" href="https://www.emqx.com/zh/apply-licenses/neuron">cập nhật License</a>
    hoặc xóa bớt một số tag dữ liệu.`,
  },
  addDriverByTemplate2405: {
    zh: `点位数超过 License 限制，模版创建驱动失败`,
    en: `The count of data points exceeds the limit of the license, and the creation of the driver fails`,
    vi: `Số điểm dữ liệu vượt quá giới hạn License, tạo trình điều khiển từ mẫu thất bại`,
  },
  addTagByNode2405: {
    zh: `点位数超过 License 限制，添加失败`,
    en: `The count of data points exceeds the license limit, and the addition fails`,
    vi: `Số điểm dữ liệu vượt quá giới hạn License, thêm thất bại`,
  },
  importTag2405: {
    zh: `点位数超过 License 限制，导入失败`,
    en: `The count of data points exceeds the license limit, and the import fails`,
    vi: `Số điểm dữ liệu vượt quá giới hạn License, nhập thất bại`,
  },
  2406: {
    zh: 'License 硬件不匹配',
    en: 'License hardware token not match',
    vi: 'Token phần cứng License không khớp',
  },
  uploadLicense2406: {
    zh: `License 与该硬件不匹配，Neuron 无法正常使用，
    请<a target="_blank" rel="noopener norefferrer" href="https://www.emqx.com/zh/apply-licenses/neuron">更新 License</a>
    或联系销售人员更新 License。`,
    en: `The license does not match the hardware, and Neuron cannot be used normally.
    Please <a target="_blank" rel="noopener norefferrer" href="https://www.emqx.com/zh/apply-licenses/neuron">update the license</a>
    or contact the sales staff to update the License.`,
    vi: `License không khớp với phần cứng, Neuron không thể hoạt động bình thường.
    Vui lòng <a target="_blank" rel="noopener norefferrer" href="https://www.emqx.com/zh/apply-licenses/neuron">cập nhật License</a>
    hoặc liên hệ bộ phận kinh doanh để cập nhật License.`,
  },
  2407: {
    zh: 'License 检测到时钟异常',
    en: 'License detect bad clock',
    vi: 'License phát hiện đồng hồ hệ thống bất thường',
  },
  2408: {
    zh: 'License 模块无效',
    en: 'License module invalid',
    vi: 'Module License không hợp lệ',
  },
  2500: {
    zh: '模板已存在',
    en: 'Template exist',
    vi: 'Mẫu đã tồn tại',
  },
  2501: {
    zh: '模板未找到',
    en: 'Template not found',
    vi: 'Không tìm thấy mẫu',
  },
  2502: {
    zh: '模板名称太长',
    en: 'Template name too long',
    vi: 'Tên mẫu quá dài',
  },
  3000: {
    zh: '插件读失败',
    en: 'Plugin read failure',
    vi: 'Plugin đọc thất bại',
  },
  3001: {
    zh: '插件写失败',
    en: 'Plugin write failure',
    vi: 'Plugin ghi thất bại',
  },
  3002: {
    zh: '插件未连接',
    en: 'Plugin disconnected',
    vi: 'Plugin ngắt kết nối',
  },
  3003: {
    zh: '插件 tag 不允许读',
    en: 'Plugin tag not allow read',
    vi: 'Tag plugin không cho phép đọc',
  },
  3004: {
    zh: '插件 tag 不允许写',
    en: 'Plugin tag not allow write',
    vi: 'Tag plugin không cho phép ghi',
  },
  3007: {
    zh: '插件 tag 类型不匹配',
    en: 'Plugin tag type mismatch',
    vi: 'Kiểu tag plugin không khớp',
  },
  3008: {
    zh: '插件 tag 值失效',
    en: 'Plugin tag value expired',
    vi: 'Giá trị tag plugin đã hết hiệu lực',
  },
  3009: {
    zh: '插件协议解析失败',
    en: 'Plugin protocol decode failure',
    vi: 'Giải mã giao thức plugin thất bại',
  },
  3010: {
    zh: '插件未运行',
    en: 'Plugin not running',
    vi: 'Plugin không chạy',
  },
  3011: {
    zh: '插件 tag 未就绪',
    en: 'Plugin tag not ready',
    vi: 'Tag plugin chưa sẵn sàng',
  },
  3012: {
    zh: '插件报文乱序',
    en: 'Plugin packet out of order',
    vi: 'Gói tin plugin sai thứ tự',
  },
  3013: {
    zh: '插件名称太长',
    en: 'Plugin name too long',
    vi: 'Tên plugin quá dài',
  },
  3014: {
    zh: '插件未找到',
    en: 'Plugin not found',
    vi: 'Không tìm thấy plugin',
  },
  3015: {
    zh: '插件设备未回复',
    en: 'Plugin device not response',
    vi: 'Thiết bị plugin không phản hồi',
  },
  3016: {
    zh: '插件不支持模板',
    en: 'Plugin not support template',
    vi: 'Plugin không hỗ trợ mẫu',
  },
  3017: {
    zh: '插件不支持写点位',
    en: 'Plugin not support write tags',
    vi: 'Plugin không hỗ trợ ghi tag',
  },
  4100: {
    zh: '字符串太长',
    en: 'String too long',
    vi: 'Chuỗi quá dài',
  },
  4101: {
    zh: '打开文件失败',
    en: 'File open failure',
    vi: 'Mở tệp thất bại',
  },
  4102: {
    zh: '读文件失败',
    en: 'File read failure',
    vi: 'Đọc tệp thất bại',
  },
  4103: {
    zh: '写文件失败',
    en: 'File write failure',
    vi: 'Ghi tệp thất bại',
  },
  10001: {
    zh: 'Opcua 点位不存在',
    en: 'Opcua tag does not exist',
    vi: 'Tag OPC UA không tồn tại',
  },
  10002: {
    zh: 'Opcua 连接配置错误',
    en: 'Opcua connection configuration error',
    vi: 'Lỗi cấu hình kết nối OPC UA',
  },
  10003: {
    zh: 'Opcua 访问超时',
    en: 'Opcua access timeout',
    vi: 'Truy cập OPC UA hết thời gian chờ',
  },
  10004: {
    zh: 'Opcua 点位不可读',
    en: 'Opcua tag is not readable',
    vi: 'Tag OPC UA không đọc được',
  },
  10005: {
    zh: 'Opcua 点位不可写',
    en: 'Opcua tag is not writable',
    vi: 'Tag OPC UA không ghi được',
  },
  10006: {
    zh: 'Opcua 点位不支持',
    en: 'Opcua tag is not supported',
    vi: 'Tag OPC UA không được hỗ trợ',
  },
  10101: {
    zh: '硬件错误',
    en: 'S7comm hardware error',
    vi: 'Lỗi phần cứng S7comm',
  },
  10103: {
    zh: '对象无访问权限',
    en: 'S7comm accessing the object not allowed',
    vi: 'S7comm không được phép truy cập đối tượng',
  },
  10105: {
    zh: '无效地址',
    en: 'S7comm invalid address',
    vi: 'S7comm địa chỉ không hợp lệ',
  },
  10106: {
    zh: '数据类型不支持',
    en: 'S7comm data type not supported',
    vi: 'S7comm kiểu dữ liệu không được hỗ trợ',
  },
  10107: {
    zh: '数据类型不一致',
    en: 'S7comm data type inconsistent',
    vi: 'S7comm kiểu dữ liệu không nhất quán',
  },
  10110: {
    zh: '对象不存在',
    en: 'S7comm object not exist',
    vi: 'S7comm đối tượng không tồn tại',
  },
  10150: {
    zh: 'COTP 连接断开',
    en: 'S7comm cotp disconnected',
    vi: 'S7comm COTP ngắt kết nối',
  },
  10151: {
    zh: 'S7 连接断开',
    en: 'S7comm disconnected',
    vi: 'S7comm đã ngắt kết nối',
  },
  10152: {
    zh: '没有值',
    en: 'S7comm no value',
    vi: 'S7comm không có giá trị',
  },
  10153: {
    zh: '值长度太短',
    en: 'S7comm value too short',
    vi: 'S7comm giá trị quá ngắn',
  },
  10200: {
    zh: '设备不存在',
    en: 'Knx no devices',
    vi: 'KNX không có thiết bị',
  },
  10400: {
    zh: '无效地址',
    en: 'Nona11 invalid address',
    vi: 'Nona11 địa chỉ không hợp lệ',
  },
  10500: {
    zh: 'Fins 连接断开',
    en: 'Fins disconnected',
    vi: 'FINS ngắt kết nối',
  },
  10501: {
    zh: 'Fins 错误',
    en: 'Fins error',
    vi: 'Lỗi FINS',
  },
  10502: {
    zh: '本地节点错误',
    en: 'Fins local node error',
    vi: 'FINS lỗi node cục bộ',
  },
  10503: {
    zh: '目标节点错误',
    en: 'Fins dest node error',
    vi: 'FINS lỗi node đích',
  },
  10504: {
    zh: '控制器错误',
    en: 'Fins communication controller error',
    vi: 'FINS lỗi bộ điều khiển truyền thông',
  },
  10505: {
    zh: '服务不受支持',
    en: 'Fins not executable',
    vi: 'FINS dịch vụ không được hỗ trợ',
  },
  10506: {
    zh: '路由表错误',
    en: 'Fins routing error',
    vi: 'FINS lỗi bảng định tuyến',
  },
  10507: {
    zh: '命令格式错误',
    en: 'Fins command format error',
    vi: 'FINS định dạng lệnh sai',
  },
  10508: {
    zh: '参数错误',
    en: 'Fins parameter error',
    vi: 'FINS tham số sai',
  },
  10509: {
    zh: '无法读取',
    en: 'Fins read not possible',
    vi: 'FINS không thể đọc',
  },
  10510: {
    zh: '无法写入',
    en: 'Fins write not possible',
    vi: 'FINS không thể ghi',
  },
  10511: {
    zh: '当前模式不可执行',
    en: 'Fins not executable in current mode',
    vi: 'FINS không thể thực thi ở chế độ hiện tại',
  },
  10512: {
    zh: '单元不存在',
    en: 'Fins no unit',
    vi: 'FINS không có đơn vị',
  },
  10513: {
    zh: '无法启动/停止',
    en: 'Fins start/stop not possible',
    vi: 'FINS không thể khởi động/dừng',
  },
  10514: {
    zh: '单元错误',
    en: 'Fins unit error',
    vi: 'FINS lỗi đơn vị',
  },
  10515: {
    zh: '命令错误',
    en: 'Fins command error',
    vi: 'FINS lỗi lệnh',
  },
  10516: {
    zh: '访问权限错误',
    en: 'Fins access error',
    vi: 'FINS lỗi quyền truy cập',
  },
  10517: {
    zh: '中止',
    en: 'Fins abort',
    vi: 'FINS hủy bỏ',
  },
  10600: {
    zh: 'Focas 错误',
    en: 'Focas error',
    vi: 'Lỗi Focas',
  },
  // 10701 - 10744
  10701: {
    zh: 'EtherNet/IP 错误',
    en: 'EtherNet/IP error',
    vi: 'Lỗi EtherNet/IP',
  },
  10797: {
    zh: 'EtherNet/IP 没有 CIP 连接',
    en: 'EtherNet/IP no CIP connection',
    vi: 'EtherNet/IP không có kết nối CIP',
  },
  10798: {
    zh: 'EtherNet/IP 数据类型不匹配',
    en: 'EtherNet/IP data type mismatch',
    vi: 'EtherNet/IP kiểu dữ liệu không khớp',
  },
  10799: {
    zh: 'EtherNet/IP 未注册session',
    en: 'EtherNet/IP no session',
    vi: 'EtherNet/IP chưa đăng ký phiên (session)',
  },
  // Profinet IO
  10800: {
    zh: 'Profinet IO 未识别',
    en: 'Profinet IO unidentified',
    vi: 'Profinet IO chưa nhận diện',
  },
  10801: {
    zh: 'Profinet IO 未连接',
    en: 'Profinet IO not connected',
    vi: 'Profinet IO chưa kết nối',
  },
  10802: {
    zh: 'Profinet IO 未准备好',
    en: 'Profinet IO not ready',
    vi: 'Profinet IO chưa sẵn sàng',
  },
  10803: {
    zh: 'Profinet IO 参数未准备好',
    en: 'Profinet IO not param end',
    vi: 'Profinet IO tham số chưa hoàn tất',
  },
  10804: {
    zh: 'Profinet IO 没有写入权限',
    en: 'Profinet IO not DWRITE',
    vi: 'Profinet IO không có quyền ghi (DWRITE)',
  },
  10805: {
    zh: 'Profinet IO 等待 HELLO 响应',
    en: 'Profinet IO wait HELLO',
    vi: 'Profinet IO đang chờ phản hồi HELLO',
  },
}
