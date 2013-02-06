//
//  SDTableViewCell.m
//  SignificantDates
//
//  Created by Chris Wagner on 5/25/12.
//

#import "PostTableViewCell.h"
#import "User.h"

@implementation PostTableViewCell

@synthesize imageView;
@synthesize nameLabel;
@synthesize textLabel;

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        // Initialization code
    }
    return self;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

//- (void)setAvatarImageForUser:(User *)user
//{
//    NSURLRequest *imageRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:user.avatarImageSrc]];
//    
//    [self.imageView setImageWithURLRequest:imageRequest
//                        placeholderImage:[UIImage imageNamed:@"profile-image-placeholder.png"]
//                                 success:^(NSURLRequest *request, NSHTTPURLResponse *response, UIImage *image) {
//                                     user.avatarImageData = UIImagePNGRepresentation(image);
//                                 }
//                                 failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error){
//                                     //handle errors here
//                                     NSLog(@"image load error");
//                                 }];
//}

@end
