macroscript VrayToGLB
	category:"DTool" 
	internalcategory:"Automate"
	tooltip:"Xuất Vray sang GLB (PBR)"
	buttonText:"Vray To GLB"
	Icon:#("MainUI", 14)
( 
	/*
	Bản Mod dành riêng cho workflow 3ds Max -> Blender
	- Giữ nguyên Multi/Sub-Object
	- Tự động dọn dẹp Color Correction
	- Tự động hút màu và xóa VRayColor
	- Fix lỗi mất màu Diffuse của glTFMaterial
	*/ 
	
	with undo on 
	(
		with animate off  
		( 
			-- Function to count bitmaps within each material in a multi-sub 
			fn CountBitmapsFromMaterial mat = 
			( 
				local found_map_count = 0 
				for x in getClassInstances bitmaptexture do 
				( 
					for y in refs.dependents x where y == mat do 
					( 
						found_map_count += 1 
					) 
				) 
				return found_map_count 
			) 
			
			-- Function to populate Glass/Liquid (empty) materials
			fn FindReplacementMaterial multiSubMat = 
			( 
				for n = 1 to multiSubMat.numsubs do 
				( 
					local subMat = multiSubMat[n] 
					if ( 
						not matchPattern subMat.name pattern:"*Glass*" ignoreCase:true and 
						not matchPattern subMat.name pattern:"*Water*" ignoreCase:true and 
						not matchPattern subMat.name pattern:"*Liquid*" ignoreCase:true 
					) then 
					( 
						return copy subMat 
					) 
				) 
				return undefined 
			) 
			
			-- Function to replace bitmaps by searching through the directory
			fn ReplaceBitmap i material_name old_pattern replace_pattern =  
			( 
				local bitmap_dir = getFilenamePath i 
				local bitmap_name = getFilenameFile i 
				
				local regex_pattern = "(?i)_?" + old_pattern + ".*" 
				local regex_replace_pattern = "(?i)_?" + replace_pattern + ".*" 
				
				local regex = dotnetObject "System.Text.RegularExpressions.Regex" regex_pattern 
				local modified_bitmap_name = regex.Replace bitmap_name "" 

				local found_strings = #() 
				for f in getFiles (bitmap_dir + "*.*") do 
				( 
					append found_strings (getFilenameFile f) 
				) 

				local matching_bitmap_names = #() 
				
				try 
				( 
					for val in found_strings where matchpattern val pattern:("*" + material_name + "_*") do 
					( 
						append matching_bitmap_names val 
					) 
				) 
				catch()  

				if matching_bitmap_names.count == 0 then 
				( 
					for s in found_strings do 
					( 
						if regex.IsMatch s modified_bitmap_name then 
						( 
							append matching_bitmap_names s 
						) 
					) 
				) 
				
				local regex_replace = dotnetObject "System.Text.RegularExpressions.Regex" regex_replace_pattern 
				local found_bitmap = "" 
				for m in matching_bitmap_names do 
				( 
					if regex_replace.IsMatch(m) then 
					( 
						found_bitmap = m 
						return (bitmap_dir + found_bitmap + (getFilenameType i)) 
					) 
				) 
			) 
			
			-- Function to populate empty glass materials
			fn FindGlassTextures i newMat missingTex = 
			( 
				local rgx_pattern = "^(\\w+?)_(\\w+?)_(\\w+?)(?:_|$)" 
				local regex = dotNetObject "System.Text.RegularExpressions.Regex" rgx_pattern 
				local match = (regex.Match newMat.name) 
				
				local bitmap_name_based_on_mtl = "" 
				
				if match.Success then 
				( 
					bitmap_name_based_on_mtl = match.Groups.Item[1].Value + "_" + match.Groups.Item[2].Value + "_" + match.Groups.Item[3].Value 
				) 

				local first_bitmap_filename = undefined

				for tex in getClassInstances bitmapTex target:rootnode do 
				( 
					first_bitmap_filename = tex.filename 
					exit
				) 
				
				local created_diffuse = undefined 
				local created_roughness = undefined 
				local bitmap_dir = undefined
				local bitmap_ext = undefined

				if i.texmap_diffuse == undefined then 
				( 
					if first_bitmap_filename != undefined then
					(
						bitmap_dir = getFilenamePath first_bitmap_filename 
						bitmap_ext = getFilenameType first_bitmap_filename 
					)
					
					try 
					( 
						newMat.baseColorMap = Bitmaptexture fileName:"" 
						newMat.baseColorMap.filename = bitmap_dir + (bitmap_name_based_on_mtl) + "_NotFound" + bitmap_ext 
						newMat.baseColorMap.filename = ReplaceBitmap (newMat.baseColorMap.filename) newMat.name "NotFound" "Base|Color|Diffuse" 
						newMat.baseColorMap.name = "basecolor" 
						created_diffuse = newMat.baseColorMap 
					) 
					catch 
					( 
						append missingTex (newMat.name as string + " - Missing: Diffuse Texture.") 
						newMat.baseColorMap = undefined 
					) 
				) 
				
				if created_diffuse != undefined then 
				( 
					if i.texmap_reflectionGlossiness == undefined then 
					( 
						try 
						( 
							newMat.roughnessMap = copy created_diffuse 
							newMat.roughnessMap.bitmap = openBitmap newMat.roughnessMap.filename gamma:1.0 
							newMat.roughnessMap.filename = ReplaceBitmap (newMat.roughnessMap.filename) newMat.name "Base|Color|Diffuse" "Rough" 
							newMat.roughnessMap.name = "roughness" 
							created_roughness = newMat.roughnessMap 
						) 
						catch 
						( 
							append missingTex (newMat.name as string + " - Missing: Roughness Texture.") 
							newMat.roughnessMap = undefined 
						) 
					) 
				) 
				
				if (created_diffuse != undefined and created_roughness != undefined) then 
				( 
					if i.texmap_metalness == undefined then 
					( 
						try 
						( 
							newMat.metalnessMap = copy created_roughness 
							newMat.metalnessMap.filename = ReplaceBitmap (newMat.metalnessMap.filename) newMat.name "Rough" "Metal" 
							newMat.metalnessMap.name = "metal"  
						) 
						catch 
						( 
							append missingTex (newMat.name as string + " - Missing: Metal Texture.") 
							newMat.metalnessMap = undefined 
						) 
					) 
					
					if i.texmap_bump == undefined then 
					( 
						try 
						( 
							newMat.normalMap = copy created_roughness 
							newMat.normalMap.filename = ReplaceBitmap (newMat.normalMap.filename) newMat.name "Rough" "Normal" 
							newMat.normalMap.name = "normal" 
						) 
						catch 
						( 
							append missingTex (newMat.name as string + " - Missing: Normal Texture.") 
							newMat.normalMap = undefined 
						) 
					) 
					
					if i.texmap_opacity == undefined then 
					( 
						try 
						( 
							newMat.AlphaMap = copy created_roughness 
							newMat.AlphaMap.filename = ReplaceBitmap (newMat.AlphaMap.filename) newMat.name "Rough" "Opacity|Alpha" 
							newMat.AlphaMap.name = "opacity" 
							newMat.alphaMode = 3
						) 
						catch 
						( 
							append missingTex (newMat.name as string + " - Missing: Opacity Texture.") 
							newMat.AlphaMap = undefined 
						) 
					) 
					
					try 
					( 
						newMat.ambientOcclusionMap = copy created_roughness 
						newMat.ambientOcclusionMap.filename = ReplaceBitmap (newMat.ambientOcclusionMap.filename) newMat.name "Rough" "AO|Ambient|Occlusion" 
						newMat.ambientOcclusionMap.name = "ao" 
					) 
					catch 
					( 
						append missingTex (newMat.name as string + " - Missing: Occlusion Texture.") 
						newMat.ambientOcclusionMap = undefined 
					) 
				) 
				
				return newMat 
			) 
			
			-- Function to convert VrayMtl to glTF material 
			fn ConvertToGltf i missingTex = 
			( 
				newMat = undefined
				(
					if iskindof (gltf_mat = execute "glTFMaterial") Material do
					(
						newMat = gltf_mat()
					)
				)
				if newMat == undefined then
				(
					messageBox ("Phiên bản 3ds Max của bạn không hỗ trợ GLTF.\nYêu cầu 3ds Max 2023 trở lên.")
					return undefined
				) 

				newMat.name = i.name 

				-- BẢN VÁ: Ép glTFMaterial nhận màu Diffuse thuần của V-Ray nếu không có map ảnh
				try (newMat.baseColor = i.diffuse) catch()

				if ((MatchPattern (i.name) pattern:"*Glass*" ignoreCase:true) or 
					(MatchPattern (i.name) pattern:"*Water*" ignoreCase:true) or 
					(MatchPattern (i.name) pattern:"*Liquid*" ignoreCase:true)) and (i.texmap_diffuse == undefined) do 
				( 
					FindGlassTextures i newMat missingTex 
					return (i = newMat) 
				) 

				-- Diffuse 
				if i.texmap_diffuse != undefined then 
				( 
					for found_bitmap in (getClassInstances Bitmaptexture target:i.texmap_diffuse) do  
					( 
						newMat.baseColorMap = found_bitmap 
					) 
				) 
				else 
				( 
					append missingTex (newMat.name as string + " - Missing: Diffuse Texture") 
				) 
				
				-- Roughness 
				if i.texmap_reflectionGlossiness != undefined then 
				( 
					for found_bitmap in (getClassInstances Bitmaptexture target:i.texmap_reflectionGlossiness) do  
					( 
						newMat.roughnessMap = found_bitmap 
					) 
				) 
				else 
				( 
					append missingTex (newMat.name as string + " - Missing: Roughness Texture") 
				) 
				
				-- Metal 
				if i.texmap_metalness != undefined then 
				( 
					for found_bitmap in (getClassInstances Bitmaptexture target:i.texmap_metalness) do  
					( 
						newMat.metalnessMap = found_bitmap 
					) 
				) 
				else 
				( 
					try 
					( 
						for found_bitmap in (getClassInstances Bitmaptexture target:i.texmap_reflectionGlossiness) do  
						( 
							newMat.metalnessMap = copy found_bitmap 
						) 
						newMat.metalnessMap.name = "metal" 
						newMat.metalnessMap.filename = ReplaceBitmap (newMat.metalnessMap.filename) newMat.name "Rough" "Metal" 
					) 
					catch 
					( 
						append missingTex (newMat.name as string + " - Missing: Metal Texture") 
						newMat.metalnessMap = undefined 
					) 
				) 
				
				-- Occlusion 
				if i.texmap_reflectionGlossiness != undefined then 
				( 
					for found_bitmap in (getClassInstances Bitmaptexture target:i.texmap_reflectionGlossiness) do  
					( 
						newMat.ambientOcclusionMap = copy found_bitmap 
					) 
					try 
					( 
						newMat.ambientOcclusionMap.name = "ao" 
						newMat.ambientOcclusionMap.filename = ReplaceBitmap (newMat.ambientOcclusionMap.filename) newMat.name "Rough" "AO|Ambient|Occlusion" 
						
						if (MatchPattern (newMat.ambientOcclusionMap.filename) pattern:"*Channel2*" ignoreCase:true) then 
						( 
							newMat.ambientOcclusionMap.coords.mapChannel = 2 
							newMat.DoubleSided = on 
						) 
					) 
					catch 
					( 
						newMat.ambientOcclusionMap = undefined 
						append missingTex (newMat.name as string + " - Missing: Occlusion Texture") 
					) 
				) 
				else 
				( 
					append missingTex (newMat.name as string + " - Missing: Occlusion Texture") 
				) 

				-- Normal 
				if i.texmap_bump != undefined then 
				( 
					if (classof i.texmap_bump == VRayNormalMap) then 
					( 
						for found_bitmap in (getClassInstances Bitmaptexture target:i.texmap_bump.normal_map) do  
						( 
							newMat.normalMap = found_bitmap 
						) 
					) 
					else if (classof i.texmap_bump == Normal_Bump) then 
					( 
						for found_bitmap in (getClassInstances Bitmaptexture target:i.texmap_bump) do  
						( 
							newMat.normalMap = found_bitmap 
						) 
					) 
					else 
					( 
						newMat.normalMap = i.texmap_bump 
						append missingTex (newMat.name as string + " - Missing: Normal Texture") 
					) 
				) 
				else 
				( 
					try 
					( 
						for found_bitmap in (getClassInstances Bitmaptexture target:i.texmap_reflectionGlossiness) do  
						( 
							newMat.normalMap = copy found_bitmap 
						) 
						newMat.normalMap.name = "normal" 
						newMat.normalMap.filename = ReplaceBitmap (newMat.normalMap.filename) newMat.name "Rough" "Normal" 
					) 
					catch 
					( 
						append missingTex (newMat.name as string + " - Missing: Normal Texture") 
						newMat.normalMap = undefined 
					) 
				) 
				
				try 
				( 
					if i.texmap_bump != undefined then 
					( 
						i.texmap_bump.normal_map.filename = substituteString i.texmap_bump.normal_map.filename "DirectX" "OpenGL" 
					) 
				) 
				catch()  
				
				-- Emission  
				if i.texmap_self_illumination != undefined then 
				( 
					for found_bitmap in (getClassInstances Bitmaptexture target:i.texmap_self_illumination) do  
					( 
						newMat.emissionMap = found_bitmap 
					) 
				) 
				
				-- Opacity 
				if i.texmap_opacity != undefined then 
				( 
					for found_bitmap in (getClassInstances Bitmaptexture target:i.texmap_opacity) do  
					( 
						newMat.AlphaMap = found_bitmap 
					) 
					
					newMat.alphaMode = 2	-- Mask mode 
					newMat.alphaCutoff = 0.1 
				) 
				else 
				( 
					try 
					( 
						for found_bitmap in (getClassInstances Bitmaptexture target:i.texmap_reflectionGlossiness) do  
						( 
							newMat.AlphaMap = copy found_bitmap 
						) 
						newMat.AlphaMap.name = "opacity" 
						newMat.AlphaMap.filename = ReplaceBitmap (newMat.AlphaMap.filename) newMat.name "Rough" "Alpha|Opacity" 

						newMat.alphaMode = 2	-- Mask mode 
						newMat.alphaCutoff = 0.1 
					) 
					catch 
					( 
						newMat.AlphaMap = undefined 
					) 
				) 
				
				return newMat
			) 

			-- ==========================================
			-- MAIN SCRIPT EXECUTION
			-- ==========================================

			local missingTex = #() 
			
			-- 1. Xóa các Modifier làm nặng lưới
			for obj in objects do 
			( 
				for mod in obj.modifiers do 
				( 
					if (mod.name == "OpenSubdiv" or mod.name == "TurboSmooth" or mod.name == "MeshSmooth") do 
					( 
						deleteModifier obj mod 
					) 
				) 
			)

			-- 2. BẢN VÁ: Gỡ toàn bộ Color_Correction để giữ lại ảnh gốc cho GLB
			for cc in (getClassInstances Color_Correction target:rootnode) do 
			( 
				if cc.map != undefined do ( replaceInstances cc cc.map )
			)

			-- 3. BẢN VÁ: Hút màu và chặt đứt dây VRayColor ở kênh Diffuse
			for vmat in (getClassInstances VRayMtl target:rootnode) do 
			( 
				if classof vmat.texmap_diffuse == VRayColor do 
				( 
					vmat.diffuse = vmat.texmap_diffuse.color 
					vmat.texmap_diffuse = undefined 
				) 
			)

			-- 4. Convert VRay2SidedMtl về VRayMtl thường (lấy mặt Front)
			for i in getClassInstances VRay2SidedMtl target:rootnode do 
			( 
				p = i.frontMtl  
				if p != undefined then replaceinstances i p 
			) 
			
			-- 5. Convert toàn bộ VRayMtl sang glTFMaterial
			for i in getClassInstances VRayMtl target:rootnode do 
			( 
				p = (ConvertToGltf i missingTex)
				if p != undefined then replaceInstances i p
			) 
			
			-- 6. Thông báo kết quả
			if missingTex.count != 0 then 
			( 
				for i in missingTex do 
				( 
					print i 
				) 
				messageBox ("Đã chuyển đổi thành công sang chuẩn glTF!\nMột số vật liệu bị thiếu ảnh (Texture). Mở cửa sổ F11 để xem chi tiết.") 
			) 
			else
			(
				messageBox ("Tuyệt vời! Đã chuyển đổi thành công 100% sang chuẩn glTF mà không thiếu Map nào.")
			)
			
			free missingTex 
		) 
	)
	-- Làm mới Asset Tracker
	ATSOps.Refresh() 
)