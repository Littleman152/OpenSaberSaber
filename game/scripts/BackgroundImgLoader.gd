extends Object

class ImgLoadRequest:
	extends RefCounted
	
	var path: String
	var file: String
	var callback_func: Callable
	var is_main_cover: bool
	var index: int
	var thread := Thread.new()

var _img_load_request_queue := LinkedList.new()

# variable used to keep track of how many threads are currently loading images
var _img_load_mutex := Mutex.new()
var _running_img_load_threads := 0

var _max_img_load_threads: int

func _init(num_threads: int = 10) -> void:
	_max_img_load_threads = num_threads

func load_texture(path: String, file: String, callback_func: Callable, is_main_cover: bool, index: int) -> void:
	var new_req := ImgLoadRequest.new()
	new_req.path = path
	new_req.file = file
	new_req.callback_func = callback_func
	new_req.is_main_cover = is_main_cover
	new_req.index = index
	_img_load_request_queue.push_back(new_req)
	
	_start_next_img_load()

func _start_next_img_load() -> void:
	_img_load_mutex.lock()
	if _img_load_request_queue.size() > 0 and _running_img_load_threads < _max_img_load_threads:
		var next_req := _img_load_request_queue.pop_front() as ImgLoadRequest
		
		if next_req and Utils.custom_thread_call(next_req.thread, _load_img_threaded, [next_req]) == OK:
			_running_img_load_threads += 1
	_img_load_mutex.unlock()

# a file name can lie (a jpg saved as .png is common), so the real format is checked
# from the first bytes of the file. returns null if the image can't be decoded.
func _image_from_buffer(data: PackedByteArray, file: String) -> Image:
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if data.size() >= 4 and data[0] == 0x89 and data[1] == 0x50 and data[2] == 0x4E and data[3] == 0x47:
		err = img.load_png_from_buffer(data)
	elif data.size() >= 3 and data[0] == 0xFF and data[1] == 0xD8 and data[2] == 0xFF:
		err = img.load_jpg_from_buffer(data)
	elif data.size() >= 12 and data.slice(0, 4).get_string_from_ascii() == "RIFF" and data.slice(8, 12).get_string_from_ascii() == "WEBP":
		err = img.load_webp_from_buffer(data)
	elif data.size() >= 2 and data[0] == 0x42 and data[1] == 0x4D:
		err = img.load_bmp_from_buffer(data)
	else:
		# unknown signature, last resort is the file extension
		var lower := file.to_lower()
		if lower.ends_with(".png"):
			err = img.load_png_from_buffer(data)
		elif lower.ends_with(".jpg") or lower.ends_with(".jpeg"):
			err = img.load_jpg_from_buffer(data)
	if err != OK or img.is_empty():
		return null
	return img

func _load_img_threaded(req: ImgLoadRequest) -> void:
	# read cover image data from file into a buffer
	var data := Utils.read_binary_file(req.path,req.file)
	if len(data) > 0:
		var img := _image_from_buffer(data, req.file)
		if img != null:
			var tex := ImageTexture.create_from_image(img)
			
			# perform callback in the form of my_callback(texture, filepath, ...)
			req.callback_func.bind(tex, req.is_main_cover, req.index).call()
		else:
			vr.log_warning("could not decode cover image %s%s" % [req.path, req.file])
	
	# this load is finished whether it worked or not, so the next one can start.
	# (before, a failed load never gave its thread slot back and slowly blocked all cover loading)
	_img_load_mutex.lock()
	_running_img_load_threads -= 1
	_img_load_mutex.unlock()
	
	# start next load if there are any waiting
	_start_next_img_load()
