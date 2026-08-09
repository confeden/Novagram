import xml.etree.ElementTree as ET
import os

def update_app_names(file_path, new_app_name, new_app_name_beta):
    """
    Reads an Android strings.xml file, updates AppName and AppNameBeta,
    and writes the file back with UTF-8 encoding.
    """
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()

        updated = False
        for string_elem in root.findall('string'):
            if string_elem.get('name') == 'AppName':
                if string_elem.text != new_app_name:
                    string_elem.text = new_app_name
                    updated = True
            elif string_elem.get('name') == 'AppNameBeta':
                if string_elem.text != new_app_name_beta:
                    string_elem.text = new_app_name_beta
                    updated = True
        
        if updated:
            # Write back with UTF-8 encoding
            tree.write(file_path, encoding='utf-8', xml_declaration=True)
            print(f"Updated {file_path}")
        else:
            print(f"No changes needed for {file_path}")

    except Exception as e:
        print(f"Error processing {file_path}: {e}")

def main():
    base_dir = "android/novagram-android/TMessagesProj/src/main/res"
    new_app_name = "NovaGram" # Replace with your desired AppName
    new_app_name_beta = "NovaGram Beta" # Replace with your desired AppNameBeta

    for root, _, files in os.walk(base_dir):
        for file in files:
            if file == "strings.xml":
                file_path = os.path.join(root, file)
                update_app_names(file_path, new_app_name, new_app_name_beta)

if __name__ == "__main__":
    main()
