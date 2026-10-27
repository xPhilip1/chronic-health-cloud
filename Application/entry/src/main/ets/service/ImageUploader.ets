// 图片选择 + 云存储上传（可复用）。
// 之前这段逻辑在 ChatPage / PostEditPage / PostDetailPage 各抄了一份，
// 头像上传这里统一收口，后续可以逐步替换掉那三处。
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { cloudStorage } from '@kit.CloudFoundationKit'
import { fileIo } from '@kit.CoreFileKit'
import { BusinessError, request } from '@kit.BasicServicesKit'

const bucket: cloudStorage.StorageBucket = cloudStorage.bucket()

// 选一张图；用户取消返回空串
export async function pickOneImage(): Promise<string> {
  let options = new photoAccessHelper.PhotoSelectOptions()
  options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
  options.maxSelectNumber = 1
  let result = await new photoAccessHelper.PhotoViewPicker().select(options)
  let uris: string[] = result.photoUris
  if (uris === undefined || uris.length === 0) {
    return ''
  }
  return uris[0]
}

// 上传本地图片到云存储并返回下载地址
// folder：云存储目录（如 'avatar'）；prefix：文件名前缀（如 'u123'）
export function uploadImage(ctx: Context, uri: string, folder: string, prefix: string): Promise<string> {
  return new Promise<string>((resolve: (v: string) => void, reject: (e: Error) => void) => {
    let fileName: string = uri.split('/').pop() as string
    let cachePath: string = ctx.cacheDir + '/' + fileName
    try {
      let srcFile = fileIo.openSync(uri)
      let dstFile = fileIo.openSync(cachePath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
      fileIo.copyFileSync(srcFile.fd, dstFile.fd)
      fileIo.closeSync(srcFile)
      fileIo.closeSync(dstFile)
    } catch (e) {
      reject(new Error('复制图片失败：' + (e as Error).message))
      return
    }
    let ext: string = fileName.indexOf('.') >= 0 ? fileName.substring(fileName.lastIndexOf('.')) : '.jpg'
    let cloudPath: string = folder + '/' + prefix + '_' + Date.now().toString() + '_' +
      Math.floor(Math.random() * 100000).toString() + ext
    bucket.uploadFile(ctx, { localPath: cachePath, cloudPath: cloudPath }).then((task: request.agent.Task) => {
      task.on('completed', () => {
        bucket.getDownloadURL(cloudPath).then((url: string) => {
          fileIo.unlink(cachePath).catch(() => {})
          resolve(url)
        }).catch((err: BusinessError) => {
          fileIo.unlink(cachePath).catch(() => {})
          reject(new Error('取下载地址失败：' + err.message))
        })
      })
      task.on('failed', () => {
        fileIo.unlink(cachePath).catch(() => {})
        reject(new Error('上传失败，请检查网络'))
      })
      task.start().catch((err: BusinessError) => {
        fileIo.unlink(cachePath).catch(() => {})
        reject(new Error('启动上传失败：' + err.message))
      })
    }).catch((err: BusinessError) => {
      fileIo.unlink(cachePath).catch(() => {})
      reject(new Error('创建上传任务失败：' + err.message))
    })
  })
}
