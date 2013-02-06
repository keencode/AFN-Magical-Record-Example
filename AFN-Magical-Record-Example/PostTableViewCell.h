//
//  SDTableViewCell.h
//  SignificantDates
//
//  Created by Chris Wagner on 5/25/12.
//

#import <UIKit/UIKit.h>
#import "UIImageView+AFNetworking.h"

@class User;

@interface PostTableViewCell : UITableViewCell

@property (nonatomic, strong) IBOutlet UIImageView *imageView;
@property (nonatomic, strong) IBOutlet UILabel *nameLabel;
@property (nonatomic, strong) IBOutlet UILabel *textLabel;

//- (void)setAvatarImageForUser:(User *)user;

@end
