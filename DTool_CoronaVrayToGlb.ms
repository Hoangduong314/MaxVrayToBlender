macroscript DTool_VrayToGLB
	category:"DTool" 
	tooltip:"DTool: Xuất Vray sang GLB (Có Bake Map)"
	buttonText:"DTool To GLB"
	Icon:#("MainUI", 14)
(
	-- Đóng bảng UI cũ nếu đang mở để tránh lỗi lặp cửa sổ
	try(destroyDialog DTool_Export_UI)catch()
	
	rollout DTool_Export_UI "DTool - PBR Exporter" width:340 height:240
	(
		groupBox grp_opts "Tùy chọn tự động hóa" pos:[10,10] width:320 height:100
		
		-- Các nút Tick tùy chọn (Mặc định được Check)
		checkbox chk_bakeCC "1. Bake Color Correction sang ảnh tĩnh (JPG)" pos:[20,30] checked:true tooltip:"Nướng node Color Correction thành ảnh thật để giữ đúng màu gốc khi sang Blender."
		checkbox chk_cleanVColor "2. Tự động rút màu từ VRayColor" pos:[20,55] checked:true tooltip:"Khắc phục lỗi vật liệu bị đen xì khi xuất sang Blender."
		checkbox chk_cleanMod "3. Xóa các Modifier làm nặng lưới" pos:[20,80] checked:true tooltip:"Tự động xóa TurboSmooth, MeshSmooth, OpenSubdiv trước khi xuất."
		
		-- Nút bấm thực thi
		button btn_run "BẮT ĐẦU CHUYỂN ĐỔI VẬT LIỆU" pos:[10,125] width:320 height:45
		
		-- Ghi chú hướng dẫn
		label lbl_info1 "Tool được tối ưu riêng cho workflow V-Ray -> Blender" pos:[25,185]
		label lbl_info2 "Chạy xong: Chọn Model -> File -> Export Selected (.glb)" pos:[25,205]

		-- Hàm xử lý chuyển đổi sang glTF
		fn ConvertToGltf i missingTex = ( 
			local newMat = undefined
			try ( if iskindof (gltf_mat = execute "glTFMaterial") Material do newMat = gltf_mat() ) catch()
			if newMat == undefined then ( messageBox "Yêu cầu 3ds Max 2023+ để hỗ trợ GLTF."; return undefined ) 
			
			newMat.name = i.name 
			-- Ép nhận màu Diffuse thuần nếu không có map ảnh
			try (newMat.baseColor = i.diffuse) catch()

			if i.texmap_diffuse != undefined then ( 
				for found_bitmap in (getClassInstances Bitmaptexture target:i.texmap_diffuse) do newMat.baseColorMap = found_bitmap 
			) else ( append missingTex (newMat.name as string + " - Thiếu map Diffuse") ) 
			
			if i.texmap_reflectionGlossiness != undefined then ( 
				for found_bitmap in (getClassInstances Bitmaptexture target:i.texmap_reflectionGlossiness) do newMat.roughnessMap = found_bitmap 
			) else ( append missingTex (newMat.name as string + " - Thiếu map Roughness") ) 
			
			if i.texmap_metalness != undefined then ( 
				for found_bitmap in (getClassInstances Bitmaptexture target:i.texmap_metalness) do newMat.metalnessMap = found_bitmap 
			) 
			
			if i.texmap_reflectionGlossiness != undefined then ( 
				for found_bitmap in (getClassInstances Bitmaptexture target:i.texmap_reflectionGlossiness) do newMat.ambientOcclusionMap = copy found_bitmap 
			) 

			if i.texmap_bump != undefined then ( 
				if (classof i.texmap_bump == VRayNormalMap) then ( 
					for found_bitmap in (getClassInstances Bitmaptexture target:i.texmap_bump.normal_map) do newMat.normalMap = found_bitmap 
				) else if (classof i.texmap_bump == Normal_Bump) then ( 
					for found_bitmap in (getClassInstances Bitmaptexture target:i.texmap_bump) do newMat.normalMap = found_bitmap 
				) else ( 
					newMat.normalMap = i.texmap_bump 
				) 
			)
			
			try ( if i.texmap_bump != undefined then i.texmap_bump.normal_map.filename = substituteString i.texmap_bump.normal_map.filename "DirectX" "OpenGL" ) catch()  
			
			if i.texmap_self_illumination != undefined then ( 
				for found_bitmap in (getClassInstances Bitmaptexture target:i.texmap_self_illumination) do newMat.emissionMap = found_bitmap 
			) 
			
			if i.texmap_opacity != undefined then ( 
				for found_bitmap in (getClassInstances Bitmaptexture target:i.texmap_opacity) do newMat.AlphaMap = found_bitmap 
				newMat.alphaMode = 2; newMat.alphaCutoff = 0.1 
			)
			return newMat
		)
		
		-- Kịch bản chạy khi bấm nút "BẮT ĐẦU CHUYỂN ĐỔI"
		on btn_run pressed do (
			with undo on (
				with animate off (
					local missingTex = #() 
					local bakedCount = 0
					local vrayCount = 0
					
					-- 1. Xóa mod làm nặng lưới
					if chk_cleanMod.checked do (
						for obj in objects do ( 
							for mod in obj.modifiers do ( 
								if (mod.name == "OpenSubdiv" or mod.name == "TurboSmooth" or mod.name == "MeshSmooth") do ( deleteModifier obj mod ) 
							) 
						)
					)

					-- 2. Bake hoặc Gỡ Color Correction
					local saveDir = getDir #export
					for cc in (getClassInstances Color_Correction target:rootnode) do ( 
						if cc.map != undefined do ( 
							if chk_bakeCC.checked then (
								-- Lấy kích thước ảnh gốc để Bake cho nét
								local resX = 1024; local resY = 1024
								if classOf cc.map == Bitmaptexture and cc.map.bitmap != undefined do (
									resX = cc.map.bitmap.width; resY = cc.map.bitmap.height
								)
								-- Đặt tên và lưu file ảnh nướng
								local fileName = saveDir + "\\" + cc.name + "_BakedCC.jpg"
								local bakedBmp = renderMap cc size:[resX, resY] fileName:fileName filter:true
								save bakedBmp; close bakedBmp
								
								-- Thay thế node lằng nhằng bằng file ảnh
								local newTex = Bitmaptexture fileName:fileName
								newTex.name = cc.name + "_Baked"
								replaceInstances cc newTex
								bakedCount += 1
							) else (
								-- Nếu không tick Bake, chỉ rút ảnh gốc ra
								replaceInstances cc cc.map
							)
						)
					)

					-- 3. Dọn VRayColor
					if chk_cleanVColor.checked do (
						for vmat in (getClassInstances VRayMtl target:rootnode) do ( 
							if classof vmat.texmap_diffuse == VRayColor do ( 
								vmat.diffuse = vmat.texmap_diffuse.color 
								vmat.texmap_diffuse = undefined 
								vrayCount += 1
							) 
						)
					)

					-- 4. Convert vật liệu 2 mặt
					for i in getClassInstances VRay2SidedMtl target:rootnode do ( 
						p = i.frontMtl  
						if p != undefined then replaceinstances i p 
					) 
					
					-- 5. Convert VrayMtl chính thành glTFMaterial
					for i in getClassInstances VRayMtl target:rootnode do ( 
						p = (ConvertToGltf i missingTex)
						if p != undefined then replaceInstances i p
					) 
					
					-- Tổng hợp thông báo kết quả
					local msg = "Đã chuyển đổi thành công sang chuẩn glTF!"
					if bakedCount > 0 do msg += "\n- Đã nướng " + bakedCount as string + " ảnh Color Correction."
					if vrayCount > 0 do msg += "\n- Đã rút màu " + vrayCount as string + " node VRayColor."
					
					if missingTex.count != 0 then ( 
						messageBox (msg + "\n\n⚠️ LƯU Ý: Có vài vật liệu bị thiếu ảnh Texture (Nhấn F11 để xem danh sách).") title:"DTool Report"
						for i in missingTex do print i 
					) else (
						messageBox (msg + "\n\nHoàn hảo! Không phát hiện lỗi. Sẵn sàng xuất file sang Blender!") title:"DTool Report"
					)
				)
			)
			ATSOps.Refresh() 
		)
	)
	
	-- Mở giao diện bảng điều khiển
	createDialog DTool_Export_UI
)