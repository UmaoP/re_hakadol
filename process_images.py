import os
from PIL import Image

def process_images():
    res_dir = "/home/umaop/work/re_hakadol/app/res"
    icon_path = os.path.join(res_dir, "icon.png")
    logo_path = os.path.join(res_dir, "logo.png")

    target_icon_path = "/home/umaop/work/re_hakadol/app/assets/icon/icon.png"
    target_logo_path = "/home/umaop/work/re_hakadol/app/assets/images/logo.png"

    # 1. アプリアイコンの余白追加 (端切れ防止)
    print("アプリアイコンの余白調整...")
    if os.path.exists(icon_path):
        icon_img = Image.open(icon_path).convert("RGBA")
        width, height = icon_img.size
        
        scale_factor = 0.70
        new_width = int(width * scale_factor)
        new_height = int(height * scale_factor)
        
        resized_icon = icon_img.resize((new_width, new_height), Image.Resampling.LANCZOS)
        
        # 透明なキャンバスの中央に配置
        padded_icon = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        offset_x = (width - new_width) // 2
        offset_y = (height - new_height) // 2
        padded_icon.paste(resized_icon, (offset_x, offset_y), resized_icon)
        
        os.makedirs(os.path.dirname(target_icon_path), exist_ok=True)
        padded_icon.save(target_icon_path, "PNG")
        print("アプリアイコンを保存しました。")

    # 2. ロゴ画像の輝度ベースの自動トリミング (暗いネオン背景を除去)
    print("ロゴ画像の輝度ベース・トリミング...")
    if os.path.exists(logo_path):
        logo_img = Image.open(logo_path).convert("RGBA")
        
        # グレースケールに変換して輝度（明るさ）を取得
        gray_img = logo_img.convert("L")
        
        # しきい値（55）以下の暗いピクセルを黒(0)にし、それより明るいピクセル（ネオン文字）を白(255)にする二値化処理
        threshold = 55
        binary_img = gray_img.point(lambda p: 255 if p > threshold else 0)
        
        # 白いネオン文字の存在する最小境界ボックス(Bounding Box)を算出
        bbox = binary_img.getbbox()
        if bbox:
            # 最小のパディングを持たせる
            pad_x = 10  # 左右の余白
            pad_y = 4   # 上下の余白
            left = max(0, bbox[0] - pad_x)
            top = max(0, bbox[1] - pad_y)
            right = min(logo_img.width, bbox[2] + pad_x)
            bottom = min(logo_img.height, bbox[3] + pad_y)
            
            # クロップ実行
            cropped_logo = logo_img.crop((left, top, right, bottom))
            
            os.makedirs(os.path.dirname(target_logo_path), exist_ok=True)
            cropped_logo.save(target_logo_path, "PNG")
            print(f"ロゴ画像をトリミング完了 -> {target_logo_path} (サイズ: {cropped_logo.size})")
        else:
            # bboxが取れない場合はそのまま保存
            os.makedirs(os.path.dirname(target_logo_path), exist_ok=True)
            logo_img.save(target_logo_path, "PNG")
            print("警告: 輝度ベースの境界ボックスが空のため、そのまま保存しました。")
            
if __name__ == "__main__":
    process_images()
