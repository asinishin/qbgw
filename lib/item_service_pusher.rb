class ItemServicePusher

  def self.add_item(item)
    if StPackage.where('sat_id = ?', item.sat_id).first
      false
    else
      StPackage.create(
        name:        item.name,
        description: item.description,
        sat_id:      item.sat_id
      )
    end
  end 

  def self.modify_item(item)
    package = StPackage.where('sat_id = ?', item.sat_id).first
    if package
      package.update_attributes(
        name:        item.name,
        description: item.description,
      )
    else
      false
    end
  end

end
