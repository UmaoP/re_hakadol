import os
from PIL import Image

def process_images():
    res_dir = "/home/umaop/work/re_hakadol/app/res"
    icon_path = os.path.join(res_dir, "icon.png")
    logo_path = os.path.join(res_dir, "logo.png")

    target_icon_path = "/home/umaop/work/re_hakadol/app/assets/icon/icon.png"
    target_logo_path = "/home/umaop/work/re_hakadol/app/assets/images/logo.png"

    # 1. アイコンの余白処理 (端切れ対策)
    print("アプリアイコンの余白調整を開始...")
    if os.path.exists(icon_path):
        icon_img = Image.open(icon_path).convert("RGBA")
        width, height = icon_img.size
        
        # Adaptive Icon のセーフエリア内に収めるため、元の画像を70%に縮小
        scale_factor = 0.70
        new_width = int(width * scale_factor)
        new_height = int(height * scale_factor)
        
        resized_icon = icon_img.resize((new_width, new_height), Image.Resampling.LANCZOS)
        
        # 元のサイズと同じサイズの透明背景のキャンバスを作成
        padded_icon = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        
        # 中央に配置
        offset_x = (width - new_width) // 2
        offset_y = (height - new_height) // 2
        padded_icon.paste(resized_icon, (offset_x, offset_y), resized_icon)
        
        # 保存
        os.makedirs(os.path.dirname(target_icon_path), exist_ok=True)
        padded_icon.save(target_icon_path, "PNG")
        print(f"アプリアイコンを調整完了 -> {target_icon_path}")
    else:
        print("エラー: icon.png が見つかりません")

    # 2. ロゴの余白自動トリミング
    print("ロゴ画像の自動トリミングを開始...")
    if os.path.exists(logo_path):
        logo_img = Image.open(logo_path).convert("RGBA")
        
        # アルファチャンネルに基づいて、文字の存在する最小境界ボックス(Bounding Box)を取得
        bbox = logo_img.getbbox()
        if bbox:
            # 若干の余白（パディング）を上下左右に持たせてトリミング（綺麗に見せるため）
            pad = 10
            left = max(0, bbox[0] - pad)
            top = max(0, bbox[1] - pad)
            right = min(logo_img.width, bbox[2] + pad)
            bottom = min(logo_img.height, bbox[3] + pad)
            
            cropped_logo = logo_img.crop((left, top, right, bottom))
            
            # 保存
            os.makedirs(os.path.dirname(target_logo_path), exist_ok=True)
            cropped_logo.save(target_logo_path, "PNG")
            print(f"ロゴ画像をトリミング完了 -> {target_logo_path} (サイズ: {cropped_logo.size})")
        else:
            # bboxが取得できない場合はそのままコピー
            os.makedirs(os.path.dirname(target_logo_path), exist_ok=True)
            logo_img.save(target_logo_path, "PNG")
            print("警告: 境界ボックスが空のため、ロゴをそのまま保存しました")
    else:
        print("エラー: logo.png が見つかりません")

if __name__ == "__main__":
    process_images()
